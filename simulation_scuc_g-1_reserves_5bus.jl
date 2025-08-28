using Pkg
#Pkg.activate("demo_dlr_sienna")
Pkg.activate("demo_scuc_sienna")
Pkg.instantiate()
#using Revise
using PowerSystems
const PSY = PowerSystems
using PowerSimulations
const PSI = PowerSimulations
using InfrastructureSystems
const IS = InfrastructureSystems

using PowerSystemCaseBuilder
using PowerNetworkMatrices
using Dates
using TimeSeries
using Logging
using HiGHS


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


mip_gap = 0.01
optimizer = optimizer_with_attributes(
    HiGHS.Optimizer,
    "parallel" => "on",
    "mip_rel_gap" => mip_gap)

#Uncoment the following line if you want to skip PowerSystemCaseBuilder setup and just load the system_to_file (and comment "sys = build_system()")
#sys = system("c_sys5_uc.json")
sys = build_system(PSITestSystems, "c_sys5_uc", add_reserves = true)

#################################### 
#INCLUDE OUTAGE AND THE RESERVE PRODUCT THAT SHOULD RESPOND TO THE OUTAGE 
####################################

#INCLUDE IN THIS DICT ALL THE RESERVE PRODUCTS THAT SHOULD RESPOND TO THE OUTAGE (GENERATORS SPECIFIED IN THE gens_outages_names LIST)
responding_reserves_dict = Dict(
    PSY.VariableReserve{ReserveUp} => "Reserve1",
    #PSY.VariableReserve{ReserveDown} => "Reserve2"  #UNCOMMENT THIS LINE IN CASE YOU WANT TO ALLOW ALSO RESERVES DOWN DURING THE CONTINGENCY
)

gens_outages_names = ["Alta"] #Add Here the names of the generators to be considered for outages in the G-k formulation
add_outages_for_scuc!( sys, responding_reserves_dict, gens_outages_names)

#Print associated Generators and Reserves to Confirm
gens = get_associated_components(sys, first(get_supplemental_attributes(GeometricDistributionForcedOutage,sys)); component_type = Generator )
println("Generators considered for outage: ", [get_name(g) for g in gens])
reserves = get_associated_components(sys, first(get_supplemental_attributes(GeometricDistributionForcedOutage,sys)); component_type = PSY.VariableReserve )
println("Reserves considered for outage: ", [get_name(r) for r in reserves])



template = ProblemTemplate(
    NetworkModel(
        PTDFPowerModel; #SecurityConstrainedPTDFPowerModel;  #PTDFPowerModel;
        use_slacks = false,
        PTDF_matrix = PTDF(sys),
    ),
)

set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template, PowerLoad, StaticPowerLoad)
set_device_model!(template, DeviceModel(Line, StaticBranch;
    use_slacks = false)) #

set_service_model!(template,
    ServiceModel(
        VariableReserve{ReserveUp},
        RangeReserveWithDeliverabilityConstraints,
        "Reserve1",
    ))

set_service_model!(template,
    ServiceModel(
        VariableReserve{ReserveDown},
        RangeReserveWithDeliverabilityConstraints,
        "Reserve2",
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

initial_date = "2024-01-01"
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

#to_json(sys, "uc_5bus_g-1.json"; pretty = true)