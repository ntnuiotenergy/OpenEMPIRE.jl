# Index types used in index sets
const NodeId = String
const GenId = String
const StorId = String
const TechId = String
const TransmissionTypeId = String
const Arc = Tuple{NodeId, NodeId}
const ArcTransmissionType = Tuple{NodeId, NodeId, TransmissionTypeId}
const NodeGen = Tuple{NodeId, GenId}
const NodeStor = Tuple{NodeId, StorId}
const NodeTech = Tuple{NodeId, TechId}
const TechGen = Tuple{TechId, GenId}

"""
    EmpireSets

Container of all index sets used to build an EMPIRE model.

`EmpireSets` collects the primary index sets (generators, storages, nodes,
technologies, transmission types, links) together with the relational subsets
that connect them (e.g. which generators belong to which node or technology).
A handful of derived lookup dictionaries (e.g. `GeneratorsByNode`) are
precomputed at construction time so that downstream model-building code can
query memberships in O(1).

# Fields

## Primary sets
- `Generator::Vector{GenId}`: all generator ids.
- `ThermalGenerators::Set{GenId}`: subset of `Generator` that is thermal.
- `HydroGenerator::Set{GenId}`: subset of `Generator` that is hydro
  (including run-of-river).
- `RegHydroGenerator::Set{GenId}`: subset of `HydroGenerator` that is
  regulated hydro with a reservoir.
- `Storage::Vector{StorId}`: all storage ids.
- `DependentStorage::Set{StorId}`: subset of `Storage` whose energy
  capacity is linked to its power capacity.
- `Technology::Vector{TechId}`: all technology ids.
- `Node::Vector{NodeId}`: all node ids.
- `OffshoreNode::Set{NodeId}`: subset of `Node` with offshore wind hubs.
- `DirectionalLink::Vector{Arc}`: directed transmission arcs `(from, to)`.
  Bidirectional corridors appear as two entries.
- `TransmissionType::Vector{TransmissionTypeId}`: available transmission
  technology types.

## Relational sets
- `TransmissionTypeOfDirectionalLink::Vector{ArcTransmissionType}`:
  tuples `(from, to, transmission_type)` assigning a type to each arc.
- `GeneratorsOfTechnology::Vector{TechGen}`: `(technology, generator)`
  membership pairs.
- `GeneratorsOfNode::Vector{NodeGen}`: `(node, generator)` membership pairs.
- `StoragesOfNode::Vector{NodeStor}`: `(node, storage)` membership pairs.

## Derived lookups (computed in the constructor)
- `GeneratorsByNode::Dict{NodeId, Vector{GenId}}`: generators present at
  each node.
- `StoragesByNode::Dict{NodeId, Vector{StorId}}`: storages present at each
  node.
- `TechsByNode::Dict{NodeId, Vector{TechId}}`: technologies represented at
  each node (via its generators).
- `GeneratorsByNodeTech::Dict{NodeTech, Vector{GenId}}`: generators at a
  node belonging to a given technology.
- `Corridors::Vector{Arc}`: undirected corridors, with each pair stored in
  canonical order `(min, max)` (see [`is_bidir`](@ref)).

# Constructors

    EmpireSets(Generator, ThermalGenerators, HydroGenerator, RegHydroGenerator,
               Storage, DependentStorage, Technology, Node, DirectionalLink,
               TransmissionType, TransmissionTypeOfDirectionalLink,
               GeneratorsOfTechnology, GeneratorsOfNode, StoragesOfNode;
               validate = true)

Positional constructor taking the primary and relational sets. Derived
lookup dictionaries are computed automatically. When `validate` is `true`
(the default) [`validate!`](@ref) is called to check internal consistency
(all referenced ids must exist in their parent sets).

    EmpireSets(; Generator = String[], ThermalGenerators = String[], ...,
                 validate = true)

Keyword constructor. All sets default to empty and any `AbstractVector` or
`AbstractSet` of `AbstractString` is accepted; values are converted to the
canonical id types (`GenId`, `StorId`, ...).

# Accessors

Prefer the exported accessor functions over field access:
[`nodes`](@ref), [`generators`](@ref), [`thermal_generators`](@ref),
[`hydro_generators`](@ref), [`reg_hydro_generators`](@ref),
[`storages`](@ref), [`dependent_storages`](@ref), [`techs`](@ref),
[`transmission_types`](@ref), [`arcs`](@ref), [`bidir_arcs`](@ref),
[`node_generators`](@ref), as well as the per-node lookups
`generators(sets, n)`, `storages(sets, n)` and the predicates
[`is_thermal`](@ref), [`is_hydro`](@ref), [`is_reg_hydro`](@ref).
"""
struct EmpireSets
    Generator::Vector{GenId}
    ThermalGenerators::Set{GenId}
    HydroGenerator::Set{GenId}
    RegHydroGenerator::Set{GenId}
    Storage::Vector{StorId}
    DependentStorage::Set{StorId}
    Technology::Vector{TechId}
    Node::Vector{NodeId}
    OffshoreNode::Set{NodeId}
    DirectionalLink::Vector{Arc}
    TransmissionType::Vector{TransmissionTypeId}
    TransmissionTypeOfDirectionalLink::Vector{ArcTransmissionType}
    GeneratorsOfTechnology::Vector{TechGen}
    GeneratorsOfNode::Vector{NodeGen}
    StoragesOfNode::Vector{NodeStor}
    GeneratorsByNode::Dict{NodeId, Vector{GenId}}
    StoragesByNode::Dict{NodeId, Vector{StorId}}
    TechsByNode::Dict{NodeId, Vector{TechId}}
    GeneratorsByNodeTech::Dict{NodeTech, Vector{GenId}}
    Corridors::Vector{Arc}
end

function EmpireSets(
    Generator::Vector{GenId},
    ThermalGenerators::Set{GenId},
    HydroGenerator::Set{GenId},
    RegHydroGenerator::Set{GenId},
    Storage::Vector{StorId},
    DependentStorage::Set{StorId},
    Technology::Vector{TechId},
    Node::Vector{NodeId},
    OffshoreNode::Set{NodeId},
    DirectionalLink::Vector{Arc},
    TransmissionType::Vector{TransmissionTypeId},
    TransmissionTypeOfDirectionalLink::Vector{ArcTransmissionType},
    GeneratorsOfTechnology::Vector{TechGen},
    GeneratorsOfNode::Vector{NodeGen},
    StoragesOfNode::Vector{NodeStor};
    validate::Bool = true,
)
    generators_by_node = Dict{NodeId, Vector{GenId}}()
    for (n, g) in GeneratorsOfNode
        push!(get!(generators_by_node, n, GenId[]), g)
    end

    storages_by_node = Dict{NodeId, Vector{StorId}}()
    for (n, s) in StoragesOfNode
        push!(get!(storages_by_node, n, StorId[]), s)
    end

    techs_by_node = Dict{NodeId, Set{TechId}}()
    for (n, g) in GeneratorsOfNode
        for (t, gg) in GeneratorsOfTechnology
            gg == g || continue
            push!(get!(techs_by_node, n, Set{TechId}()), t)
        end
    end
    techs_by_node_vec = Dict{NodeId, Vector{TechId}}(n => collect(ts) for (n, ts) in techs_by_node)

    generators_by_node_tech = Dict{NodeTech, Set{GenId}}()
    for (n, g) in GeneratorsOfNode
        for (t, gg) in GeneratorsOfTechnology
            gg == g || continue
            push!(get!(generators_by_node_tech, (n, t), Set{GenId}()), g)
        end
    end
    generators_by_node_tech_vec = Dict{NodeTech, Vector{GenId}}(k => collect(v) for (k, v) in generators_by_node_tech)

    corridor_set = Set{Arc}()
    for (m, n) in DirectionalLink
        push!(corridor_set, is_bidir(m, n) ? (m, n) : (n, m))
    end
    corridors = collect(corridor_set)

    sets = EmpireSets(
        Generator,
        ThermalGenerators,
        HydroGenerator,
        RegHydroGenerator,
        Storage,
        DependentStorage,
        Technology,
        Node,
        OffshoreNode,
        DirectionalLink,
        TransmissionType,
        TransmissionTypeOfDirectionalLink,
        GeneratorsOfTechnology,
        GeneratorsOfNode,
        StoragesOfNode,
        generators_by_node,
        storages_by_node,
        techs_by_node_vec,
        generators_by_node_tech_vec,
        corridors,
    )

    validate && validate!(sets)
    return sets
end

function EmpireSets(
    ;
    Generator::AbstractVector{<:AbstractString} = String[],
    ThermalGenerators::Union{AbstractVector{<:AbstractString}, AbstractSet{<:AbstractString}} = String[],
    HydroGenerator::Union{AbstractVector{<:AbstractString}, AbstractSet{<:AbstractString}} = String[],
    RegHydroGenerator::Union{AbstractVector{<:AbstractString}, AbstractSet{<:AbstractString}} = String[],
    Storage::AbstractVector{<:AbstractString} = String[],
    DependentStorage::Union{AbstractVector{<:AbstractString}, AbstractSet{<:AbstractString}} = String[],
    Technology::AbstractVector{<:AbstractString} = String[],
    Node::AbstractVector{<:AbstractString} = String[],
    OffshoreNode::Union{AbstractVector{<:AbstractString}, AbstractSet{<:AbstractString}} = String[],
    DirectionalLink::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} = Tuple{String, String}[],
    TransmissionType::AbstractVector{<:AbstractString} = String[],
    TransmissionTypeOfDirectionalLink::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString, <:AbstractString}} =
        Tuple{String, String, String}[],
    GeneratorsOfTechnology::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} = Tuple{String, String}[],
    GeneratorsOfNode::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} = Tuple{String, String}[],
    StoragesOfNode::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} = Tuple{String, String}[],
    validate::Bool = true,
)
    return EmpireSets(
        String.(Generator),
        Set(String.(collect(ThermalGenerators))),
        Set(String.(collect(HydroGenerator))),
        Set(String.(collect(RegHydroGenerator))),
        String.(Storage),
        Set(String.(collect(DependentStorage))),
        String.(Technology),
        String.(Node),
        Set(String.(collect(OffshoreNode))),
        Arc[(String(m), String(n)) for (m, n) in DirectionalLink],
        String.(TransmissionType),
        ArcTransmissionType[(String(m), String(n), String(tt)) for (m, n, tt) in TransmissionTypeOfDirectionalLink],
        TechGen[(String(t), String(g)) for (t, g) in GeneratorsOfTechnology],
        NodeGen[(String(n), String(g)) for (n, g) in GeneratorsOfNode],
        NodeStor[(String(n), String(s)) for (n, s) in StoragesOfNode];
        validate = validate,
    )
end

# Accessors, prefer to use this instead of direct field access
nodes(sets::EmpireSets) = sets.Node
offshore_nodes(sets::EmpireSets) = sets.OffshoreNode
generators(sets::EmpireSets) = sets.Generator
thermal_generators(sets::EmpireSets) = sets.ThermalGenerators
hydro_generators(sets::EmpireSets) = sets.HydroGenerator
reg_hydro_generators(sets::EmpireSets) = sets.RegHydroGenerator
storages(sets::EmpireSets) = sets.Storage
dependent_storages(sets::EmpireSets) = sets.DependentStorage
techs(sets::EmpireSets) = sets.Technology
transmission_types(sets::EmpireSets) = sets.TransmissionType
arcs(sets::EmpireSets) = sets.DirectionalLink
bidir_arcs(sets::EmpireSets) = sets.Corridors
is_bidir(m, n) = m < n
is_offshore(sets::EmpireSets, n) = n in sets.OffshoreNode
generators(sets::EmpireSets, n) = get(sets.GeneratorsByNode, n, GenId[])
node_generators(sets::EmpireSets) = sets.GeneratorsOfNode
is_thermal(sets::EmpireSets, g) = g in sets.ThermalGenerators
is_hydro(sets::EmpireSets, g) = g in sets.HydroGenerator
is_reg_hydro(sets::EmpireSets, g) = g in sets.RegHydroGenerator
storages(sets::EmpireSets, n) = get(sets.StoragesByNode, n, StorId[])
node_storages(sets::EmpireSets) = sets.StoragesOfNode
techs(sets::EmpireSets, n) = get(sets.TechsByNode, n, TechId[])
generators_tech(sets::EmpireSets, n, t) = get(sets.GeneratorsByNodeTech, (n, t), GenId[])

function _check_unique(name::AbstractString, items)
    seen = Set{eltype(items)}()
    dups = eltype(items)[]
    for x in items
        x in seen ? push!(dups, x) : push!(seen, x)
    end
    isempty(dups) || throw(ArgumentError("Duplicate entries in $name: $(unique(dups))"))
end

function _check_no_empty(name::AbstractString, items)
    any(isempty, items) && throw(ArgumentError("$name contains empty-string id(s)"))
end

function validate!(sets::EmpireSets)
    node_set = Set(nodes(sets))
    gen_set = Set(generators(sets))
    storage_set = Set(storages(sets))
    tech_set = Set(techs(sets))
    transmission_types_set = Set(transmission_types(sets))

    # Uniqueness of primary ids
    _check_unique("Generator", generators(sets))
    _check_unique("Storage", storages(sets))
    _check_unique("Technology", techs(sets))
    _check_unique("Node", nodes(sets))
    _check_unique("TransmissionType", transmission_types(sets))

    # No empty-string ids in primary sets
    _check_no_empty("Generator", generators(sets))
    _check_no_empty("Storage", storages(sets))
    _check_no_empty("Technology", techs(sets))
    _check_no_empty("Node", nodes(sets))
    _check_no_empty("TransmissionType", transmission_types(sets))

    # Subset checks for generator/storage categories
    isempty(setdiff(thermal_generators(sets), gen_set)) ||
        throw(ArgumentError("All ThermalGenerators must exist in Generator"))
    isempty(setdiff(hydro_generators(sets), gen_set)) ||
        throw(ArgumentError("All HydroGenerator entries must exist in Generator"))
    isempty(setdiff(reg_hydro_generators(sets), gen_set)) ||
        throw(ArgumentError("All RegHydroGenerator entries must exist in Generator"))
    isempty(setdiff(dependent_storages(sets), storage_set)) ||
        throw(ArgumentError("All DependentStorage entries must exist in Storage"))
    isempty(setdiff(offshore_nodes(sets), node_set)) ||
        throw(ArgumentError("All OffshoreNode entries must exist in Node"))

    # Subset relations between generator categories
    isempty(setdiff(reg_hydro_generators(sets), hydro_generators(sets))) ||
        throw(ArgumentError("All RegHydroGenerator entries must also be in HydroGenerator"))
    let overlap = intersect(thermal_generators(sets), hydro_generators(sets))
        isempty(overlap) ||
            throw(ArgumentError("Generators classified as both thermal and hydro: $(collect(overlap))"))
    end

    for (n, g) in node_generators(sets)
        n in node_set || throw(ArgumentError("Unknown node in GeneratorsOfNode: $n"))
        g in gen_set || throw(ArgumentError("Unknown generator in GeneratorsOfNode: $g"))
    end

    for (n, s) in node_storages(sets)
        n in node_set || throw(ArgumentError("Unknown node in StoragesOfNode: $n"))
        s in storage_set || throw(ArgumentError("Unknown storage in StoragesOfNode: $s"))
    end

    for (t, g) in sets.GeneratorsOfTechnology
        t in tech_set || throw(ArgumentError("Unknown technology in GeneratorsOfTechnology: $t"))
        g in gen_set || throw(ArgumentError("Unknown generator in GeneratorsOfTechnology: $g"))
    end

    arc_set = Set(arcs(sets))
    for (m, n) in arcs(sets)
        m in node_set || throw(ArgumentError("Unknown from-node in DirectionalLink: $m"))
        n in node_set || throw(ArgumentError("Unknown to-node in DirectionalLink: $n"))
        # No self-loops
        m == n && throw(ArgumentError("Self-loop in DirectionalLink: ($m, $n)"))
    end

    for (m, n, tt) in sets.TransmissionTypeOfDirectionalLink
        (m, n) in arc_set || throw(ArgumentError("Unknown arc in TransmissionTypeOfDirectionalLink: ($m, $n)"))
        tt in transmission_types_set ||
            throw(ArgumentError("Unknown transmission type in TransmissionTypeOfDirectionalLink: $tt"))
    end

    # No duplicate relational pairs
    _check_unique("GeneratorsOfNode", node_generators(sets))
    _check_unique("StoragesOfNode", node_storages(sets))
    _check_unique("GeneratorsOfTechnology", sets.GeneratorsOfTechnology)
    _check_unique("DirectionalLink", arcs(sets))
    _check_unique("TransmissionTypeOfDirectionalLink", sets.TransmissionTypeOfDirectionalLink)

    # Every generator belongs to at least one technology
    let gen_tech_counts = Dict{GenId, Int}()
        for (_, g) in sets.GeneratorsOfTechnology
            gen_tech_counts[g] = get(gen_tech_counts, g, 0) + 1
        end
        missing_tech = [g for g in generators(sets) if !haskey(gen_tech_counts, g)]
        isempty(missing_tech) ||
            @warn "Generators not assigned to any technology" generators = missing_tech
    end

    # Every generator is assigned to at least one node
    let assigned = Set(g for (_, g) in node_generators(sets))
        unassigned = [g for g in generators(sets) if !(g in assigned)]
        isempty(unassigned) ||
            @warn "Generators not assigned to any node" generators = unassigned
    end

    # Every arc has at least one transmission type
    let arcs_with_type = Set((m, n) for (m, n, _) in sets.TransmissionTypeOfDirectionalLink)
        without_type = [a for a in arcs(sets) if !(a in arcs_with_type)]
        isempty(without_type) ||
            @warn "DirectionalLinks without an assigned TransmissionType" arcs = without_type
    end

    return sets
end
