#######################################################################
# -----------------  STRUCTS TO READ SCUC DATAFRAMES  -----------------
#######################################################################
abstract type SCUCMappings end
struct OutageUUID2ComponentMappings <: SCUCMappings
    component_name_to_uuid::Dict{String, String}
    uuid_to_component_name::Dict{String, String}  
    uuid_to_reserve_name::Union{Dict{String, String}, Nothing}
end

abstract type SCUCResults end
struct PostContingencyResults <: SCUCResults
    variables::Dict{String, DataFrame}
    flow_expressions::Dict{String, DataFrame}
end