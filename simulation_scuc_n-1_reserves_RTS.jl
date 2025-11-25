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

sys = build_system(PSISystems, "modified_RTS_GMLC_DA_sys")
lines_by_area = Dict{String, Any}()
transformers_by_area = Dict{String, Any}()
for area in get_components(Area, sys)
    @info("Getting lines and transformers for area: $(get_name(area))")
    lines = get_components(l -> l.arc.from.area == area && l.arc.to.area == area, Line, sys)
    @show get_name.(lines)
    lines_by_area[get_name(area)] = lines
    transformers = get_components(t -> t.arc.from.area == area && t.arc.to.area == area, TapTransformer, sys)
    @show get_name.(transformers)
    transformers_by_area[get_name(area)] = transformers
end

# Add Here the names of the generators to be considered for outages in the G-k formulation
lines_outages_names_list = [ ["A34"], ["A4"], ["A22"], ["A8"], ["A25-1"], ["A12-1"], ["A33-1"], ["A32-1"], 
                             ["B5"], ["B2"], ["B23"], ["B19"], ["B28"], ["B32-1"], ["B33-1"], ["B13-2"],
                             ["C21"], ["C3"], ["C26"], ["C9"], ["C30"], ["C10"], ["C31-2"], ["C25-1"] ] #,
outage_mappings = add_multiple_outages_to_scuc!(sys, PSY.Line, lines_outages_names_list, Outage_type=GeometricDistributionForcedOutage)

template = ProblemTemplate(
    NetworkModel(
        PTDFPowerModel;
        use_slacks = false,
        PTDF_matrix = PTDF(sys),
        LODF_matrix = LODF(sys),
    ),
)

set_device_model!(template, ThermalStandard, ThermalStandardUnitCommitment)
set_device_model!(template, RenewableDispatch, RenewableFullDispatch)
set_device_model!(template, RenewableNonDispatch, FixedOutput)
set_device_model!(template, HydroDispatch, HydroDispatchRunOfRiver)

set_device_model!(template, PowerLoad, StaticPowerLoad)

set_device_model!(template, DeviceModel(Line, SecurityConstrainedStaticBranch;
    use_slacks = false)) #
set_device_model!(template, DeviceModel(TapTransformer, SecurityConstrainedStaticBranch;
    use_slacks = false)) #
set_device_model!(template, DeviceModel(TwoTerminalGenericHVDCLine,
                                HVDCTwoTerminalLossless))

set_service_model!(template,
    ServiceModel(
        VariableReserve{ReserveUp},
        RangeReserve,
        "Spin_Up_R1",
    ))
set_service_model!(template,
    ServiceModel(
        VariableReserve{ReserveUp},
        RangeReserve,
        "Spin_Up_R2",
    ))
set_service_model!(template,
    ServiceModel(
        VariableReserve{ReserveUp},
        RangeReserve,
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


build!(sim; console_level = Logging.Info)
 
execute!(sim)

results = SimulationResults(sim)
uc = get_decision_problem_results(results, "UC")

therm_df = read_realized_variable(uc, "ActivePowerVariable__ThermalStandard", table_format=TableFormat.WIDE)
Pline_df = read_realized_variable(uc, "FlowActivePowerVariable__Line", table_format=TableFormat.WIDE)

scuc_res_line = get_scuc_results(
    uc,
    outage_mappings,
    "",
)
scuc_res_transformer = get_scuc_results(
    uc,
    outage_mappings,
    "",
)


vars = model.internal.container.variables
keys_var = collect(keys(vars))
constr = model.internal.container.constraints
keys_constr = collect(keys(constr))
expr = model.internal.container.expressions
keys_expr = collect(keys(expr))