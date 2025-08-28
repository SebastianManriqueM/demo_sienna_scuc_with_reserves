using Pkg
#Pkg.activate("demo_dlr_sienna")
Pkg.activate("demo_scuc_sienna")
Pkg.instantiate()
#using Revise
using PowerSystems
const PSY = PowerSystems
using PowerSimulations
const PSI = PowerSimulations
using HydroPowerSimulations
const HPS = HydroPowerSimulations
using InfrastructureSystems
const IS = InfrastructureSystems

using PowerSystemCaseBuilder
using PowerNetworkMatrices
using Dates
using TimeSeries
using Logging
using HiGHS
using Xpress

function add_outages_for_scuc!(
    sys::PSY.System,
    responding_reserves_dict::Dict{DataType, String},
    gens_outages_names::Vector{String},
)
    for gen_name in gens_outages_names
        # --- Create Outage Data ---
        transition_data = GeometricDistributionForcedOutage(;
            mean_time_to_recovery = 10,  # Units of hours - This value does not have any influence for G-1 formulation
            outage_transition_probability = 0.9999,  # Probability for outage per hour - This value does not have any influence for G-1 formulation
        )
        
        #ADD ALL THE GENERATORS YOU WANT TO CONSIDER IN A SIMULTANEOUS OUTAGE (THIS ALLOW TO ASSESS G-1, G-2... G-k CASES)
        for gen_name in gens_outages_names
            gen = get_component(PSY.Generator, sys, gen_name) #Brighton (Infeasible), Solitude (infinite Iteration),  Park City, Alta, Sundance
            add_supplemental_attribute!(sys, gen, transition_data)
        end

        #YOU NEED TO ADD THE SAME OUTAGE INSTANCE FOR BOTH THE GENERATOR AND THE RESERVE PRODUCT(S) THAT SHOULD RESPOND TO THE OUTAGE
        for (reserve, reserve_name) in responding_reserves_dict
            reserve_product = get_component(reserve, sys, reserve_name)
            add_supplemental_attribute!(sys, reserve_product, transition_data)
        end
        
    end

end

function add_multiple_outages_to_scuc!(
    sys::PSY.System,
    responding_reserves_list::Vector{Dict{DataType, String}},
    gens_outages_names_list::Vector{Vector{String}})

    for (responding_reserves_dict, gens_outages_names) in zip(responding_reserves_list, gens_outages_names_list)
        add_outages_for_scuc!(sys, responding_reserves_dict, gens_outages_names)
    end

end



mip_gap = 0.01
# optimizer = optimizer_with_attributes(
#     HiGHS.Optimizer,
#     "parallel" => "on",
#     "mip_rel_gap" => mip_gap)
optimizer = optimizer_with_attributes(
    Xpress.Optimizer,
    "MIPRELSTOP" => mip_gap)

#Uncoment the following line if you want to skip PowerSystemCaseBuilder setup and just load the system_to_file (and comment "sys = build_system()")
#sys = system("RTS_g-1.json")
sys = build_system(PSISystems, "modified_RTS_GMLC_DA_sys")#THIS SYSTEM HAS 4 DIFFERENT RESERVES UP DEFINED:

#PRINT THE RESERVE PRODUCTS AND ITS CONTRIBUTTING DEVICES AND AREAS
reserves_up = get_components(VariableReserve{ReserveUp}, sys)

contributing_devices_dict = Dict{String, Vector{String}}()
contributing_devices_area_dict = Dict{String, Vector{String}}()
for reserve in reserves_up
    println("Reserve Up Product: ", get_name(reserve))
    contributing_devices_dict[get_name(reserve)] = get_name.(get_contributing_devices(sys, reserve))
    contributing_devices_area_dict[get_name(reserve)] = get_name.(get_area.(get_bus.(get_contributing_devices(sys, reserve))))
    println("  Contributing Devices: ", contributing_devices_dict[get_name(reserve)])
    println("  Contributing Devices Area: ", contributing_devices_area_dict[get_name(reserve)])
end
#################################### 
#INCLUDE OUTAGE AND THE RESERVE PRODUCT THAT SHOULD RESPOND TO THE OUTAGE 
####################################

#INCLUDE IN THIS DICT ALL THE RESERVE PRODUCTS THAT SHOULD RESPOND TO THE OUTAGE (GENERATORS SPECIFIED IN THE gens_outages_names LIST)
responding_reserves_list = [Dict(PSY.VariableReserve{ReserveUp} => "Spin_Up_R1")
                            Dict(PSY.VariableReserve{ReserveUp} => "Spin_Up_R2")
                            Dict(PSY.VariableReserve{ReserveUp} => "Spin_Up_R3")]

gens_outages_names_list = [["123_STEAM_2"], ["202_STEAM_3"],["322_CT_6"]] #Add Here the names of the generators to be considered for outages in the G-k formulation
add_multiple_outages_to_scuc!(sys, responding_reserves_list, gens_outages_names_list)


#Print associated Generators and Reserves to Confirm
for outage in get_supplemental_attributes(GeometricDistributionForcedOutage,sys)
    println("Outage Instance ID: ", IS.get_uuid(outage))
    gens = get_associated_components(sys, outage; component_type = Generator )
    println("Generators considered for outage: ", [get_name(g) for g in gens])
    reserves = get_associated_components(sys, outage; component_type = PSY.VariableReserve )
    println("Reserves considered for outage: ", [get_name(r) for r in reserves])
end


template = ProblemTemplate(
    NetworkModel(
        PTDFPowerModel; #SecurityConstrainedPTDFPowerModel;  #PTDFPowerModel;
        use_slacks = false,
        PTDF_matrix = PTDF(sys),
    ),
)

set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template, RenewableNonDispatch, FixedOutput)
set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)

set_device_model!(template, PowerLoad, StaticPowerLoad)

set_device_model!(template, DeviceModel(Line, StaticBranch;
    use_slacks = false)) #
set_device_model!(template, DeviceModel(TapTransformer, StaticBranch;
    use_slacks = false)) #
set_device_model!(template, DeviceModel(TwoTerminalGenericHVDCLine,
                                HVDCTwoTerminalLossless))

set_service_model!(template,
    ServiceModel(
        VariableReserve{ReserveUp},
        RangeReserveWithDeliverabilityConstraints,
        "Spin_Up_R1",
    ))
set_service_model!(template,
    ServiceModel(
        VariableReserve{ReserveUp},
        RangeReserveWithDeliverabilityConstraints,
        "Spin_Up_R2",
    ))
set_service_model!(template,
    ServiceModel(
        VariableReserve{ReserveUp},
        RangeReserveWithDeliverabilityConstraints,
        "Spin_Up_R3",
    ))

set_service_model!(template,
    ServiceModel(
        VariableReserve{ReserveUp},
        RangeReserve,
        "Reg_Up",
    ))
set_service_model!(template,
    ServiceModel(
        VariableReserve{ReserveUp},
        RangeReserve,
        "Reg_Down",
    ))

model = DecisionModel(
    template,
    sys;
    name = "UC",
    optimizer = optimizer,
    system_to_file = false,
    initialize_model = true,
    check_numerical_bounds = false,
    optimizer_solve_log_print = true,
    direct_mode_optimizer = false,
    rebuild_model = false,
    store_variable_names = true,
    calculate_conflict = false,
)

models = SimulationModels(;
    decision_models = [model],
)

DA_sequence = SimulationSequence(;
    models = models,
    ini_cond_chronology = InterProblemChronology(),
)

initial_date = "2020-01-01"
steps_sim = 2
current_date = string(today())
sim = Simulation(;
    name = current_date * "_5bus" * "_" * "_" * string(steps_sim) * "steps",
    steps = steps_sim,
    models = models,
    initial_time = DateTime(string(initial_date, "T00:00:00")),
    sequence = DA_sequence,
    simulation_folder = tempdir(),#".",   tempdir()
)


build!(sim; console_level = Logging.Debug)
 
execute!(sim)

results = SimulationResults(sim)
uc = get_decision_problem_results(results, "UC")

therm_df = read_realized_variable(uc, "ActivePowerVariable__ThermalStandard")
Pline_df = read_realized_variable(uc, "FlowActivePowerVariable__Line")


vars = model.internal.container.variables
keys_var = collect(keys(vars))
constr = model.internal.container.constraints
keys_constr = collect(keys(constr))
expr = model.internal.container.expressions
keys_expr = collect(keys(expr))

to_json(sys, "RTS_g-1.json"; pretty = true)