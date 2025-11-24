include("utils_scuc_definitions.jl")

#######################################################################
# ----------------- FUNCTIONS TO READ SCUC DATAFRAMES -----------------
#######################################################################

function get_outage_uuid_mappings(
    sys::PSY.System;
    Outage_type::DataType=GeometricDistributionForcedOutage,
    )::OutageUUID2ComponentMappings
    #These Dict were designed only for G-1 analysis purposes
    component_name_to_uuid_dict = Dict{String, String}()
    uuid_to_component_name_dict = Dict{String, String}()  
    uuid_to_reserve_name_dict = Dict{String, String}()
    for outage in get_supplemental_attributes( Outage_type, sys )
        string_uuid = string(IS.get_uuid(outage))
        @info("Outage Instance ID: $string_uuid")
        gens = get_associated_components(sys, outage; component_type = Generator )
        @info("Outaged Generators: ", [get_name(g) for g in gens])
        reserves = get_associated_components(sys, outage; component_type = PSY.VariableReserve )
        @info("Reserves that respond to the outage: ", [get_name(r) for r in reserves])
        component_name_to_uuid_dict[get_name(gens[1])] = string_uuid
        uuid_to_reserve_name_dict[string_uuid] = get_name(reserves[1])
        uuid_to_component_name_dict[string_uuid] = get_name(gens[1])
    end
    return OutageUUID2ComponentMappings(
        component_name_to_uuid_dict,
        uuid_to_component_name_dict,
        uuid_to_reserve_name_dict,
    )
end

struct ReserveOutageData
    reserve_name::String
    contributing_devices::Vector{String}
    contributing_devices_area::Vector{String}
end


#######################################################################
# ---------- FUNCTIONS TO ADD OUTAGE SUPLEMMENTAL ATTRIBUTES ----------
#######################################################################
function add_outages_for_scuc!(
    sys::PSY.System,
    responding_reserves_dict::Dict{DataType, String},
    gens_outages_names::Vector{String};
    Outage_type::DataType=GeometricDistributionForcedOutage,
)
    for gen_name in gens_outages_names
        # --- Create Outage Data ---
        transition_data = Outage_type(;
            #The following parameters do not have any influence in the G-1 formulation, but are required to create the outage instance
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
    gens_outages_names_list_by_reserve::Vector{Vector{Vector{String}}};
    Outage_type::DataType=GeometricDistributionForcedOutage,
    )::OutageUUID2ComponentMappings
    for (responding_reserves_dict, gens_outages_names_list) in zip(responding_reserves_list, gens_outages_names_list_by_reserve)

        for outage_gens_names in gens_outages_names_list
            add_outages_for_scuc!(sys, responding_reserves_dict, outage_gens_names, Outage_type=Outage_type)
        end
    end
    return get_outage_uuid_mappings(sys, Outage_type=Outage_type)
end


#######################################################################
# ------------------- FUNCTIONS TO READ SCUC RESULTS ------------------
#######################################################################
function get_name_from_names_list(
    names_list::Vector{String},
    target_suffix::String;
    target_prefix::String="PostContingency"
)
    filtered_names = filter( x -> startswith(x, target_prefix) && contains(x, target_suffix), names_list)
    if length(filtered_names) <= 0
        @error("No PostContingency names found for reserve: $target_suffix")
    elseif length(filtered_names) > 1
        @warn("Multiple names found for target: $target_suffix. Using the first one: $(filtered_names[1]).")
    end
    return filtered_names[1]
end

function get_post_contingency_expression_name(
    results::PowerSimulations.SimulationProblemResults,
    meta_name::String,
)
    expresion_names = list_expression_names(results)
    return get_name_from_names_list(expresion_names, meta_name, target_prefix="PostContingency")
end

function get_post_contingency_variable_name(
    results::PowerSimulations.SimulationProblemResults,
    meta_name::String,
)
    variable_names = list_variable_names(results)
    return get_name_from_names_list(variable_names, meta_name, target_prefix="PostContingency")
end

function get_scuc_results(
    results::PowerSimulations.SimulationProblemResults,
    outage_mappings::OutageUUID2ComponentMappings,
    meta_name::String,
)
    expression_name = get_post_contingency_expression_name(results, meta_name)
    variable_name = get_post_contingency_variable_name(results, meta_name)

    reserve_deployment = read_realized_variable(results, variable_name)
    post_cont_flow = read_realized_expression(results, expression_name)

    post_contingency_results_dict = split_dataframe_by_outage(
        post_cont_flow,
        outage_mappings.uuid_to_component_name,
    )

    variables_dict = split_dataframe_by_outage(
        reserve_deployment,
        outage_mappings.uuid_to_component_name,
    )

    return PostContingencyResults(
        variables_dict,
        post_contingency_results_dict,
    )
end


function split_dataframe_by_outage(
    df::DataFrame,
    uuid_to_device_dict::Dict{String, String}
    )
    result_dict = Dict{String, DataFrame}()
    
    for (uuid, device_name) in uuid_to_device_dict
        # Filter rows for this specific uuid
        filtered_df = filter(row -> row.name == uuid, df)
        
        if nrow(filtered_df) > 0
            # Pivot the data: DateTime as index, name2 values as columns
            pivoted_df = unstack(filtered_df, :DateTime, :name2, :value)
            result_dict[device_name] = pivoted_df
        end
    end
    
    return result_dict
end