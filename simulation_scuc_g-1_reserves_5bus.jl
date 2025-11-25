using Pkg
Pkg.activate("demo_scuc_sienna")
Pkg.instantiate()
#using Revise
using InfrastructureSystems
const IS = InfrastructureSystems
using PowerSystems
const PSY = PowerSystems
using PowerSystemCaseBuilder
const PSB = PowerSystemCaseBuilder
using PowerNetworkMatrices

using PowerSimulations
const PSI = PowerSimulations
using HydroPowerSimulations
const HPS = HydroPowerSimulations

using Dates
using TimeSeries
using DataFrames
using Logging
using HiGHS
using Xpress
include("utils_scuc.jl")

mip_gap = 0.01
# optimizer = optimizer_with_attributes(
#     HiGHS.Optimizer,
#     "parallel" => "on",
#     "mip_rel_gap" => mip_gap)
optimizer = optimizer_with_attributes(
    Xpress.Optimizer,
    "MIPRELSTOP" => mip_gap)

sys = build_system(PSITestSystems, "c_sys5_uc", add_reserves = true)


#PRINT THE RESERVE PRODUCTS AND ITS CONTRIBUTTING DEVICES AND AREAS
reserves_up = get_components(VariableReserve{ReserveUp}, sys)

contributing_devices_dict = Dict{String, Vector{String}}()
for reserve in reserves_up
    println("Reserve Up Product: ", get_name(reserve))
    contributing_devices_dict[get_name(reserve)] = get_name.(get_contributing_devices(sys, reserve))
    println("  Contributing Devices: ", contributing_devices_dict[get_name(reserve)])
end


#################################### 
#INCLUDE OUTAGE AND THE RESERVE PRODUCT THAT SHOULD RESPOND TO THE OUTAGE 
####################################    
#INCLUDE IN THIS DICT ALL THE RESERVE PRODUCTS THAT SHOULD RESPOND TO THE OUTAGE (GENERATORS SPECIFIED IN THE gens_outages_names LIST)
responding_reserves_list = [Dict(PSY.VariableReserve{ReserveUp} => "Reserve1")]

# Add Here the names of the generators to be considered for outages in the G-k formulation
gens_outages_names_list = [ [ ["Alta"] ] ] #, , 
outage_mappings = add_multiple_outages_to_scuc!(sys, responding_reserves_list, gens_outages_names_list, Outage_type=GeometricDistributionForcedOutage)


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
        RampReserveWithDeliverabilityConstraints,
        "Reserve1",
    ))

set_service_model!(template,
    ServiceModel(
        VariableReserve{ReserveDown},
        RangeReserve,
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

therm_df = read_realized_variable(uc, "ActivePowerVariable__ThermalStandard", table_format=TableFormat.WIDE)
Pline_df = read_realized_variable(uc, "FlowActivePowerVariable__Line", table_format=TableFormat.WIDE)

scuc_res_r1 = get_scuc_results(
    uc,
    outage_mappings,
    "Reserve1",
)


vars = model.internal.container.variables
keys_var = collect(keys(vars))
constr = model.internal.container.constraints
keys_constr = collect(keys(constr))
expr = model.internal.container.expressions
keys_expr = collect(keys(expr))

#to_json(sys, "uc_5bus_g-1.json"; pretty = true)