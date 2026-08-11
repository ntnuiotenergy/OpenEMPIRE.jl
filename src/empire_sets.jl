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
const NaturalGasTerminalNode = Tuple{NodeId, String}
const HydrogenTerminalNode = Tuple{NodeId, String}

"""
    NaturalGasSets

Natural-gas index sets and precomputed adjacency lookups. An empty instance
represents a disabled natural-gas module without introducing abstract fields.
"""
struct NaturalGasSets
    Node::Vector{NodeId}
    DirectionalLink::Vector{Arc}
    Terminal::Vector{String}
    TerminalsOfNode::Vector{NaturalGasTerminalNode}
    OnshoreNode::Set{NodeId}
    Generator::Set{GenId}
    Incoming::Dict{NodeId, Vector{NodeId}}
    Outgoing::Dict{NodeId, Vector{NodeId}}
    TerminalsByNode::Dict{NodeId, Vector{String}}
end

"""
    HydrogenSets

Hydrogen and CO₂ index sets plus sparse network lookups. An empty instance
represents a disabled module and keeps the electricity-only data model unchanged.
"""
struct HydrogenSets
    ProductionNode::Vector{NodeId}
    Generator::Set{GenId}
    ReformerLocation::Vector{NodeId}
    ReformerPlant::Vector{String}
    Storage::Vector{String}
    StoragesOfNode::Vector{Tuple{NodeId, String}}
    TerminalNode::Vector{NodeId}
    Terminal::Vector{String}
    TerminalsOfNode::Vector{HydrogenTerminalNode}
    CO2SequestrationNode::Vector{NodeId}
    DirectionalLink::Vector{Arc}
    Corridor::Vector{Arc}
    CO2DirectionalLink::Vector{Arc}
    RepurposableGasCorridor::Vector{Arc}
    Incoming::Dict{NodeId, Vector{NodeId}}
    Outgoing::Dict{NodeId, Vector{NodeId}}
    TerminalsByNode::Dict{NodeId, Vector{String}}
end

function HydrogenSets(
    ;
    ProductionNode::AbstractVector{<:AbstractString} = String[],
    Generator::Union{AbstractVector{<:AbstractString}, AbstractSet{<:AbstractString}} = String[],
    ReformerLocation::AbstractVector{<:AbstractString} = String[],
    ReformerPlant::AbstractVector{<:AbstractString} = String[],
    Storage::AbstractVector{<:AbstractString} = String[],
    StoragesOfNode::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} =
        Tuple{String, String}[],
    TerminalNode::AbstractVector{<:AbstractString} = String[],
    Terminal::AbstractVector{<:AbstractString} = String[],
    TerminalsOfNode::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} =
        Tuple{String, String}[],
    CO2SequestrationNode::AbstractVector{<:AbstractString} = String[],
    DirectionalLink::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} =
        Tuple{String, String}[],
    CO2DirectionalLink::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} =
        Tuple{String, String}[],
    RepurposableGasCorridor::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} =
        Tuple{String, String}[],
)
    links = Arc[(String(from), String(to)) for (from, to) in DirectionalLink]
    corridors = unique(Arc[minmax(from, to) for (from, to) in links])
    incoming = Dict{NodeId, Vector{NodeId}}()
    outgoing = Dict{NodeId, Vector{NodeId}}()
    for (from, to) in links
        push!(get!(outgoing, from, NodeId[]), to)
        push!(get!(incoming, to, NodeId[]), from)
    end
    terminal_pairs = HydrogenTerminalNode[
        (String(node), String(terminal)) for (node, terminal) in TerminalsOfNode
    ]
    terminals_by_node = Dict{NodeId, Vector{String}}()
    for (node, terminal) in terminal_pairs
        push!(get!(terminals_by_node, node, String[]), terminal)
    end
    return HydrogenSets(
        String.(ProductionNode),
        Set(String.(collect(Generator))),
        String.(ReformerLocation),
        String.(ReformerPlant),
        String.(Storage),
        Tuple{NodeId, String}[(String(node), String(storage)) for (node, storage) in StoragesOfNode],
        String.(TerminalNode),
        String.(Terminal),
        terminal_pairs,
        String.(CO2SequestrationNode),
        links,
        corridors,
        Arc[(String(from), String(to)) for (from, to) in CO2DirectionalLink],
        unique(Arc[(String(from), String(to)) for (from, to) in RepurposableGasCorridor]),
        incoming,
        outgoing,
        terminals_by_node,
    )
end

function NaturalGasSets(
    ;
    Node::AbstractVector{<:AbstractString} = String[],
    DirectionalLink::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} =
        Tuple{String, String}[],
    Terminal::AbstractVector{<:AbstractString} = String[],
    TerminalsOfNode::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} =
        Tuple{String, String}[],
    OnshoreNode::Union{AbstractVector{<:AbstractString}, AbstractSet{<:AbstractString}} =
        String[],
    Generator::Union{AbstractVector{<:AbstractString}, AbstractSet{<:AbstractString}} =
        String[],
)
    nodes = String.(Node)
    links = Arc[(String(from), String(to)) for (from, to) in DirectionalLink]
    terminals = String.(Terminal)
    terminal_nodes =
        NaturalGasTerminalNode[(String(node), String(terminal)) for
                               (node, terminal) in TerminalsOfNode]
    incoming = Dict{NodeId, Vector{NodeId}}()
    outgoing = Dict{NodeId, Vector{NodeId}}()
    for (from, to) in links
        push!(get!(outgoing, from, NodeId[]), to)
        push!(get!(incoming, to, NodeId[]), from)
    end
    terminals_by_node = Dict{NodeId, Vector{String}}()
    for (node, terminal) in terminal_nodes
        push!(get!(terminals_by_node, node, String[]), terminal)
    end
    return NaturalGasSets(
        nodes,
        links,
        terminals,
        terminal_nodes,
        Set(String.(collect(OnshoreNode))),
        Set(String.(collect(Generator))),
        incoming,
        outgoing,
        terminals_by_node,
    )
end

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
- `OffshoreWindFarmNode::Set{NodeId}`: subset of `Node` holding offshore wind
  farms. Their own installed generation caps the transmission corridors adjacent
  to them, so a member with no generators would pin those corridors to zero
  capacity; `validate!` rejects that rather than letting it happen silently.
- `OffshoreEnergyHub::Set{NodeId}`: subset of `Node` holding offshore energy
  hubs — junctions that route power between wind farms and shore without
  generating anything themselves. Disjoint from `OffshoreWindFarmNode`: a hub is
  limited by its converter capacity, not by generation it does not have.
  Currently read and validated only; the converter formulation is not ported yet.
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
    OffshoreWindFarmNode::Set{NodeId}
    OffshoreEnergyHub::Set{NodeId}
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
    NaturalGas::NaturalGasSets
    Hydrogen::HydrogenSets
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
    OffshoreWindFarmNode::Set{NodeId},
    OffshoreEnergyHub::Set{NodeId},
    DirectionalLink::Vector{Arc},
    TransmissionType::Vector{TransmissionTypeId},
    TransmissionTypeOfDirectionalLink::Vector{ArcTransmissionType},
    GeneratorsOfTechnology::Vector{TechGen},
    GeneratorsOfNode::Vector{NodeGen},
    StoragesOfNode::Vector{NodeStor};
    NaturalGas::NaturalGasSets = NaturalGasSets(),
    Hydrogen::HydrogenSets = HydrogenSets(),
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
        OffshoreWindFarmNode,
        OffshoreEnergyHub,
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
        NaturalGas,
        Hydrogen,
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
    OffshoreWindFarmNode::Union{AbstractVector{<:AbstractString}, AbstractSet{<:AbstractString}} = String[],
    OffshoreEnergyHub::Union{AbstractVector{<:AbstractString}, AbstractSet{<:AbstractString}} = String[],
    DirectionalLink::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} = Tuple{String, String}[],
    TransmissionType::AbstractVector{<:AbstractString} = String[],
    TransmissionTypeOfDirectionalLink::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString, <:AbstractString}} =
        Tuple{String, String, String}[],
    GeneratorsOfTechnology::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} = Tuple{String, String}[],
    GeneratorsOfNode::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} = Tuple{String, String}[],
    StoragesOfNode::AbstractVector{<:Tuple{<:AbstractString, <:AbstractString}} = Tuple{String, String}[],
    NaturalGas::NaturalGasSets = NaturalGasSets(),
    Hydrogen::HydrogenSets = HydrogenSets(),
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
        Set(String.(collect(OffshoreWindFarmNode))),
        Set(String.(collect(OffshoreEnergyHub))),
        Arc[(String(m), String(n)) for (m, n) in DirectionalLink],
        String.(TransmissionType),
        ArcTransmissionType[(String(m), String(n), String(tt)) for (m, n, tt) in TransmissionTypeOfDirectionalLink],
        TechGen[(String(t), String(g)) for (t, g) in GeneratorsOfTechnology],
        NodeGen[(String(n), String(g)) for (n, g) in GeneratorsOfNode],
        NodeStor[(String(n), String(s)) for (n, s) in StoragesOfNode];
        NaturalGas,
        Hydrogen,
        validate = validate,
    )
end

# Accessors, prefer to use this instead of direct field access
nodes(sets::EmpireSets) = sets.Node
offshore_wind_farm_nodes(sets::EmpireSets) = sets.OffshoreWindFarmNode
offshore_energy_hubs(sets::EmpireSets) = sets.OffshoreEnergyHub
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
is_offshore_wind_farm(sets::EmpireSets, n) = n in sets.OffshoreWindFarmNode
is_offshore_energy_hub(sets::EmpireSets, n) = n in sets.OffshoreEnergyHub
generators(sets::EmpireSets, n) = get(sets.GeneratorsByNode, n, GenId[])
node_generators(sets::EmpireSets) = sets.GeneratorsOfNode
is_thermal(sets::EmpireSets, g) = g in sets.ThermalGenerators
is_hydro(sets::EmpireSets, g) = g in sets.HydroGenerator
is_reg_hydro(sets::EmpireSets, g) = g in sets.RegHydroGenerator
storages(sets::EmpireSets, n) = get(sets.StoragesByNode, n, StorId[])
node_storages(sets::EmpireSets) = sets.StoragesOfNode
techs(sets::EmpireSets, n) = get(sets.TechsByNode, n, TechId[])
generators_tech(sets::EmpireSets, n, t) = get(sets.GeneratorsByNodeTech, (n, t), GenId[])
natural_gas_sets(sets::EmpireSets) = sets.NaturalGas
natural_gas_nodes(sets::EmpireSets) = sets.NaturalGas.Node
natural_gas_links(sets::EmpireSets) = sets.NaturalGas.DirectionalLink
natural_gas_terminals(sets::EmpireSets) = sets.NaturalGas.Terminal
natural_gas_terminal_nodes(sets::EmpireSets) = sets.NaturalGas.TerminalsOfNode
natural_gas_onshore_nodes(sets::EmpireSets) = sets.NaturalGas.OnshoreNode
natural_gas_generators(sets::EmpireSets) = sets.NaturalGas.Generator
natural_gas_incoming(sets::EmpireSets, node) =
    get(sets.NaturalGas.Incoming, node, NodeId[])
natural_gas_outgoing(sets::EmpireSets, node) =
    get(sets.NaturalGas.Outgoing, node, NodeId[])
natural_gas_terminals(sets::EmpireSets, node) =
    get(sets.NaturalGas.TerminalsByNode, node, String[])
has_natural_gas(sets::EmpireSets) = !isempty(natural_gas_nodes(sets))
hydrogen_sets(sets::EmpireSets) = sets.Hydrogen
hydrogen_nodes(sets::EmpireSets) = sets.Hydrogen.ProductionNode
hydrogen_generators(sets::EmpireSets) = sets.Hydrogen.Generator
has_hydrogen(sets::EmpireSets) = !isempty(hydrogen_nodes(sets))

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
    isempty(setdiff(offshore_wind_farm_nodes(sets), node_set)) ||
        throw(ArgumentError("All OffshoreWindFarmNode entries must exist in Node"))
    isempty(setdiff(offshore_energy_hubs(sets), node_set)) ||
        throw(ArgumentError("All OffshoreEnergyHub entries must exist in Node"))
    let both = intersect(offshore_wind_farm_nodes(sets), offshore_energy_hubs(sets))
        isempty(both) || throw(ArgumentError(
            "Nodes listed as both an offshore wind farm and an energy hub: $(sort(collect(both))). " *
            "A wind farm's corridors are capped by its own generation; a hub's are capped by its " *
            "converter capacity. A node cannot be both.",
        ))
    end
    # A wind farm caps its corridors by its own installed generation, so one with no
    # generators would force them to zero capacity and silently disconnect the node.
    # This is what "all nodes minus onshore nodes" produces when it sweeps up energy
    # hubs and platforms, so reject it here instead of solving a disconnected model.
    let barren = [n for n in offshore_wind_farm_nodes(sets) if isempty(generators(sets, n))]
        isempty(barren) || throw(ArgumentError(
            "OffshoreWindFarmNode entries with no generators: $(sort(barren)). " *
            "Their transmission corridors would be capped at zero. Energy hubs belong in " *
            "OffshoreEnergyHub; nodes that are merely offshore belong in neither set.",
        ))
    end

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

    gas = natural_gas_sets(sets)
    _check_unique("NaturalGas.Node", gas.Node)
    _check_unique("NaturalGas.DirectionalLink", gas.DirectionalLink)
    _check_unique("NaturalGas.Terminal", gas.Terminal)
    _check_unique("NaturalGas.TerminalsOfNode", gas.TerminalsOfNode)
    _check_no_empty("NaturalGas.Node", gas.Node)
    _check_no_empty("NaturalGas.Terminal", gas.Terminal)
    isempty(setdiff(Set(gas.Node), node_set)) ||
        throw(ArgumentError("All natural-gas nodes must exist in Node"))
    isempty(setdiff(gas.OnshoreNode, node_set)) ||
        throw(ArgumentError("All natural-gas onshore nodes must exist in Node"))
    isempty(setdiff(gas.Generator, gen_set)) ||
        throw(ArgumentError("All natural-gas generators must exist in Generator"))
    gas_node_set = Set(gas.Node)
    gas_terminal_set = Set(gas.Terminal)
    for (from, to) in gas.DirectionalLink
        from in gas_node_set ||
            throw(ArgumentError("Unknown from-node in NaturalGas.DirectionalLink: $from"))
        to in gas_node_set ||
            throw(ArgumentError("Unknown to-node in NaturalGas.DirectionalLink: $to"))
        from == to &&
            throw(ArgumentError("Self-loop in NaturalGas.DirectionalLink: ($from, $to)"))
    end
    for (node, terminal) in gas.TerminalsOfNode
        node in gas_node_set ||
            throw(ArgumentError("Unknown node in NaturalGas.TerminalsOfNode: $node"))
        terminal in gas_terminal_set ||
            throw(ArgumentError("Unknown terminal in NaturalGas.TerminalsOfNode: $terminal"))
    end
    for (node, generator) in node_generators(sets)
        generator in gas.Generator || continue
        node in gas_node_set || throw(ArgumentError(
            "Natural-gas generator $generator is assigned to non-gas node $node",
        ))
    end

    hydrogen = hydrogen_sets(sets)
    for (name, values) in (
        ("Hydrogen.ProductionNode", hydrogen.ProductionNode),
        ("Hydrogen.ReformerLocation", hydrogen.ReformerLocation),
        ("Hydrogen.ReformerPlant", hydrogen.ReformerPlant),
        ("Hydrogen.Storage", hydrogen.Storage),
        ("Hydrogen.StoragesOfNode", hydrogen.StoragesOfNode),
        ("Hydrogen.TerminalNode", hydrogen.TerminalNode),
        ("Hydrogen.Terminal", hydrogen.Terminal),
        ("Hydrogen.TerminalsOfNode", hydrogen.TerminalsOfNode),
        ("Hydrogen.CO2SequestrationNode", hydrogen.CO2SequestrationNode),
        ("Hydrogen.DirectionalLink", hydrogen.DirectionalLink),
        ("Hydrogen.CO2DirectionalLink", hydrogen.CO2DirectionalLink),
        ("Hydrogen.RepurposableGasCorridor", hydrogen.RepurposableGasCorridor),
    )
        _check_unique(name, values)
    end
    isempty(setdiff(Set(hydrogen.ProductionNode), node_set)) ||
        throw(ArgumentError("All Hydrogen production nodes must exist in Node"))
    isempty(setdiff(Set(hydrogen.ReformerLocation), node_set)) ||
        throw(ArgumentError("All Hydrogen reformer locations must exist in Node"))
    isempty(setdiff(Set(hydrogen.TerminalNode), node_set)) ||
        throw(ArgumentError("All Hydrogen terminal nodes must exist in Node"))
    isempty(setdiff(Set(hydrogen.CO2SequestrationNode), node_set)) ||
        throw(ArgumentError("All CO2 sequestration nodes must exist in Node"))
    isempty(setdiff(hydrogen.Generator, gen_set)) ||
        throw(ArgumentError("All Hydrogen generators must exist in Generator"))
    hydrogen_node_set = Set(hydrogen.ProductionNode)
    for (from, to) in hydrogen.DirectionalLink
        from in hydrogen_node_set && to in hydrogen_node_set ||
            throw(ArgumentError("Hydrogen link ($from, $to) references a non-production node"))
        from == to && throw(ArgumentError("Self-loop in Hydrogen.DirectionalLink: ($from, $to)"))
    end
    terminal_node_set = Set(hydrogen.TerminalNode)
    terminal_set = Set(hydrogen.Terminal)
    for (node, terminal) in hydrogen.TerminalsOfNode
        node in terminal_node_set ||
            throw(ArgumentError("Unknown node in Hydrogen.TerminalsOfNode: $node"))
        terminal in terminal_set ||
            throw(ArgumentError("Unknown terminal in Hydrogen.TerminalsOfNode: $terminal"))
    end
    hydrogen_storage_set = Set(hydrogen.Storage)
    for (node, storage) in hydrogen.StoragesOfNode
        node in hydrogen_node_set ||
            throw(ArgumentError("Unknown node in Hydrogen.StoragesOfNode: $node"))
        storage in hydrogen_storage_set ||
            throw(ArgumentError("Unknown storage in Hydrogen.StoragesOfNode: $storage"))
    end
    if !isempty(hydrogen.ProductionNode)
        isempty(setdiff(gas.OnshoreNode, hydrogen_node_set)) || throw(ArgumentError(
            "All natural-gas onshore nodes must be Hydrogen production nodes when Hydrogen is enabled",
        ))
        isempty(setdiff(Set(hydrogen.ReformerLocation), gas_node_set)) ||
            throw(ArgumentError("All Hydrogen reformer locations must be natural-gas nodes"))
        isempty(setdiff(Set(hydrogen.CO2SequestrationNode), gas.OnshoreNode)) ||
            throw(ArgumentError("All CO2 sequestration nodes must be onshore nodes"))
        isempty(setdiff(Set(hydrogen.TerminalNode), hydrogen_node_set)) ||
            throw(ArgumentError("All Hydrogen terminal nodes must be production nodes"))
    end

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
