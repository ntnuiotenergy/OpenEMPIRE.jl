"""
    EmpireParams

Mutable container for all numeric input parameters of an EMPIRE model.

Fields are grouped by category (financial, generator, transmission, storage,
node, general, stochastic and processed parameters) and store either scalar
values, `Dict`s keyed by id (e.g. generator, storage, node) or pair of ids
(e.g. `(node, generator)`, `(from_node, to_node)`), with values that are
either `Float64` constants or `TimeProfile`s.

All fields default to empty / `nothing`, so an `EmpireParams` can be
constructed incrementally and filled in by the data-loading routines. The
accessor helpers defined below (`load`, `gencap_avail`, `rampup_cap`, ...)
should be preferred over direct field access — they fall back to the
documented `DEFAULT_*` constants when a value is missing.

Use [`validate`](@ref) to check value ranges and (optionally) verify that
all dictionary keys reference ids present in a given [`EmpireSets`](@ref).
"""
Base.@kwdef mutable struct EmpireParams
    # Financial parameters
    WACC::Union{Nothing, Float64} = nothing
    discountRate::Union{Nothing, Float64} = nothing

    # Generator inputs from file
    genCapitalCost::Dict{String, TimeProfile}                       = Dict{String, TimeProfile}()
    genFixedOMCost::Dict{String, TimeProfile}                       = Dict{String, TimeProfile}()
    genVariableOMCost::Dict{String, Float64}                        = Dict{String, Float64}()
    genFuelCost::Dict{String, TimeProfile}                          = Dict{String, TimeProfile}()
    CCSCostTSVariable::Union{Nothing, TimeProfile}                  = nothing
    genEfficiency::Dict{String, TimeProfile}                        = Dict{String, TimeProfile}()
    genRefInitCap::Dict{Tuple{String,String}, Float64}              = Dict{Tuple{String,String}, Float64}()
    genScaleInitCap::Dict{String, TimeProfile}                      = Dict{String, TimeProfile}()
    genInitCap::Dict{Tuple{String,String}, TimeProfile}             = Dict{Tuple{String,String}, TimeProfile}()
    genMaxBuiltCap::Dict{Tuple{String,String}, TimeProfile}         = Dict{Tuple{String,String}, TimeProfile}()
    genMaxInstalledCapRaw::Dict{Tuple{String,String}, Float64}      = Dict{Tuple{String,String}, Float64}()
    genMaxInstalledCap::Dict{Tuple{String,String}, TimeProfile}     = Dict{Tuple{String,String}, TimeProfile}()
    genRampUpCap::Dict{String, Float64}                             = Dict{String, Float64}()
    genCapAvailType::Dict{String, Float64}                          = Dict{String, Float64}()
    genCO2Content::Dict{String, Float64}                            = Dict{String, Float64}()
    genLifetime::Dict{String, Float64}                              = Dict{String, Float64}()

    # Transmission inputs from file
    transmissionInitCap::Dict{Tuple{String,String}, TimeProfile}            = Dict{Tuple{String,String}, TimeProfile}()
    transmissionMaxBuiltCap::Dict{Tuple{String,String}, TimeProfile}        = Dict{Tuple{String,String}, TimeProfile}()
    transmissionMaxInstalledCap::Dict{Tuple{String,String}, TimeProfile}    = Dict{Tuple{String,String}, TimeProfile}()
    transmissionLength::Dict{Tuple{String,String}, Float64}                 = Dict{Tuple{String,String}, Float64}()
    transmissionTypeCapitalCost::Dict{String, TimeProfile}                  = Dict{String, TimeProfile}()
    transmissionTypeFixedOMCost::Dict{String, TimeProfile}                  = Dict{String, TimeProfile}()
    lineEfficiency::Dict{Tuple{String,String}, Float64}                     = Dict{Tuple{String,String}, Float64}()
    transmissionLifetime::Dict{Tuple{String,String}, Float64}               = Dict{Tuple{String,String}, Float64}()

    # Storage inputs from file
    storageBleedEff::Dict{String, Float64}                              = Dict{String, Float64}()
    storageChargeEff::Dict{String, Float64}                             = Dict{String, Float64}()
    storageDischargeEff::Dict{String, Float64}                          = Dict{String, Float64}()
    storagePowToEnergy::Dict{String, Float64}                           = Dict{String, Float64}()
    storENCapitalCost::Dict{String, TimeProfile}                        = Dict{String, TimeProfile}()
    storENFixedOMCost::Dict{String, TimeProfile}                        = Dict{String, TimeProfile}()
    storENInitCap::Dict{Tuple{String,String}, TimeProfile}              = Dict{Tuple{String,String}, TimeProfile}()
    storENMaxBuiltCap::Dict{Tuple{String,String}, TimeProfile}          = Dict{Tuple{String,String}, TimeProfile}()
    storENMaxInstalledCap::Dict{Tuple{String,String}, Float64}          = Dict{Tuple{String,String}, Float64}()
    storOperationalInit::Dict{String, Float64}                          = Dict{String, Float64}()
    storPWCapitalCost::Dict{String, TimeProfile}                        = Dict{String, TimeProfile}()
    storPWFixedOMCost::Dict{String, TimeProfile}                        = Dict{String, TimeProfile}()
    storPWInitCap::Dict{Tuple{String,String}, TimeProfile}              = Dict{Tuple{String,String}, TimeProfile}()
    storPWMaxBuiltCap::Dict{Tuple{String,String}, TimeProfile}          = Dict{Tuple{String,String}, TimeProfile}()
    storPWMaxInstalledCap::Dict{Tuple{String,String}, Float64}          = Dict{Tuple{String,String}, Float64}()
    storageLifetime::Dict{String, Float64}                              = Dict{String, Float64}()

    # Node inputs from file
    nodeLostLoadCost::Dict{String, TimeProfile}     = Dict{String, TimeProfile}()
    sloadAnnualDemand::Dict{String, TimeProfile}    = Dict{String, TimeProfile}()
    maxHydroNode::Dict{String, Float64}             = Dict{String, Float64}()

    # General parameters from file
    CO2cap::Union{Nothing, TimeProfile}     = nothing
    CO2price::Union{Nothing, TimeProfile}   = nothing

    # Stochastic parameters
    sloadRaw::Dict{String, TimeProfile}                             = Dict{String, TimeProfile}()
    sload::Dict{String, TimeProfile}                                = Dict{String, TimeProfile}()
    genCapAvail::Dict{Tuple{String,String}, TimeProfile}            = Dict{Tuple{String,String}, TimeProfile}()
    maxRegHydroGenRaw::Dict{String, TimeProfile}                    = Dict{String, TimeProfile}()
    maxRegHydroGen::Dict{String, TimeProfile}                       = Dict{String, TimeProfile}()

    # Processed parameters
    genInvCost::Dict{String, TimeProfile}                           = Dict{String, TimeProfile}()
    storENInvCost::Dict{String, TimeProfile}                        = Dict{String, TimeProfile}()
    storPWInvCost::Dict{String, TimeProfile}                        = Dict{String, TimeProfile}()
    transmissionInvCost::Dict{Tuple{String,String}, TimeProfile}    = Dict{Tuple{String,String}, TimeProfile}()
    genMargCost::Dict{String, TimeProfile}                          = Dict{String, TimeProfile}()
end

# Default values used by the accessor helpers below.
#
# Whenever a parameter is missing from its underlying `Dict` (i.e. the model
# data does not specify a value for the given generator / storage / node /
# arc), these constants are returned by the corresponding accessor.

# Loads / generation quantities default to zero (no demand, no production)
const DEFAULT_LOAD              = 0.0
const DEFAULT_MAX_HYDRO_GEN     = 0.0

# Initial installed capacities default to zero
const DEFAULT_GEN_INIT_CAP      = 0.0
const DEFAULT_STOR_EN_INIT_CAP  = 0.0
const DEFAULT_STOR_PW_INIT_CAP  = 0.0
const DEFAULT_TRANS_INIT_CAP    = 0.0

# Build / installed capacity limits default to `nothing`, meaning no limits
const DEFAULT_MAX_BUILD_CAP     = nothing
const DEFAULT_MAX_INST_CAP      = nothing
const DEFAULT_TRANS_MAX_BUILD   = nothing
const DEFAULT_TRANS_MAX_INST    = nothing
const DEFAULT_MAX_HYDRO_NODE    = nothing

# Efficiencies / availability factors default to 1.0 (lossless / fully available)
const DEFAULT_RAMPUP_CAP        = 1.0
const DEFAULT_BLEED_EFF         = 1.0
const DEFAULT_CHARGE_EFF        = 1.0
const DEFAULT_DISCHARGE_EFF     = 1.0
const DEFAULT_LINE_EFF          = 1.0
const DEFAULT_POWER_TO_ENERGY   = 1.0

# Operational initial state of storages defaults to empty
const DEFAULT_STORAGE_INIT      = 0.0

# Lifetimes default to 40 years
const DEFAULT_GEN_LIFETIME      = 40
const DEFAULT_STORAGE_LIFETIME  = 40
const DEFAULT_TRANS_LIFETIME    = 40

# Investment / marginal costs default to zero
const DEFAULT_GEN_INVEST_COST    = 0.0
const DEFAULT_STOR_EN_INVEST_COST = 0.0
const DEFAULT_STOR_PW_INVEST_COST = 0.0
const DEFAULT_TRANS_INVEST_COST  = 0.0
const DEFAULT_GEN_MARGINAL_COST  = 0.0

# Penalty cost for unserved load (high so it is rarely optimal to shed load)
const DEFAULT_LOST_LOAD_COST     = 1000.0

# Helper functions to get parameter values with default fallbacks, the model should
# only use these functions to access parameter values

# General properties
load(par, n, t) = haskey(par.sload, n) ? par.sload[n][t] : DEFAULT_LOAD

# Generator properties
gencap_avail(par, n, g, t) =
    haskey(par.genCapAvail, (n, g)) ? par.genCapAvail[(n, g)][t] : par.genCapAvailType[g]
rampup_cap(par, g) = get(par.genRampUpCap, g, DEFAULT_RAMPUP_CAP)
max_build_cap(par, n, gt, sp) = (n, gt) in keys(par.genMaxBuiltCap) ? par.genMaxBuiltCap[(n, gt)][sp] : DEFAULT_MAX_BUILD_CAP
max_inst_cap(par, n, gt, sp) = (n, gt) in keys(par.genMaxInstalledCap) ? par.genMaxInstalledCap[(n, gt)][sp] : DEFAULT_MAX_INST_CAP
gen_lifetime(par, g) = get(par.genLifetime, g, DEFAULT_GEN_LIFETIME)
gencap_init(par, n, g, sp) = (n, g) in keys(par.genInitCap) ? par.genInitCap[(n, g)][sp] : DEFAULT_GEN_INIT_CAP
max_hydro_gen(par, n, sc) = haskey(par.maxRegHydroGen, n) ? par.maxRegHydroGen[n][sc] : DEFAULT_MAX_HYDRO_GEN
max_hydro_node(par, n) = get(par.maxHydroNode, n, DEFAULT_MAX_HYDRO_NODE)

# Storage properties
bleed_eff(par, s) = get(par.storageBleedEff, s, DEFAULT_BLEED_EFF)
charge_eff(par, s) = get(par.storageChargeEff, s, DEFAULT_CHARGE_EFF)
discharge_eff(par, s) = get(par.storageDischargeEff, s, DEFAULT_DISCHARGE_EFF)
storage_init(par, s) = get(par.storOperationalInit, s, DEFAULT_STORAGE_INIT)
lifetime_storage(par, s) = get(par.storageLifetime, s, DEFAULT_STORAGE_LIFETIME)
stor_cap_init_en(par, n, s, sp) = haskey(par.storENInitCap, (n, s)) ? par.storENInitCap[(n, s)][sp] : DEFAULT_STOR_EN_INIT_CAP
stor_cap_init_pow(par, n, s, sp) = haskey(par.storPWInitCap, (n, s)) ? par.storPWInitCap[(n, s)][sp] : DEFAULT_STOR_PW_INIT_CAP
power_to_energy(par, s) = get(par.storagePowToEnergy, s, DEFAULT_POWER_TO_ENERGY)

# Transmission properties
trans_cap_init(par, m, n, sp) = haskey(par.transmissionInitCap, (m, n)) ? par.transmissionInitCap[(m, n)][sp] : DEFAULT_TRANS_INIT_CAP
trans_lifetime(par, m, n) = get(par.transmissionLifetime, (m, n), DEFAULT_TRANS_LIFETIME)
trans_max_build_cap(par, m, n, sp) = haskey(par.transmissionMaxBuiltCap, (m, n)) ? par.transmissionMaxBuiltCap[(m, n)][sp] : DEFAULT_TRANS_MAX_BUILD
trans_max_inst_cap(par, m, n, sp) = haskey(par.transmissionMaxInstalledCap, (m, n)) ? par.transmissionMaxInstalledCap[(m, n)][sp] : DEFAULT_TRANS_MAX_INST
line_eff(par, m, n) = get(par.lineEfficiency, (m, n), DEFAULT_LINE_EFF)

# Cost properties
gen_invest_cost(par, g, sp) = haskey(par.genInvCost, g) ? par.genInvCost[g][sp] : DEFAULT_GEN_INVEST_COST
stor_en_invest_cost(par, s, sp) = haskey(par.storENInvCost, s) ? par.storENInvCost[s][sp] : DEFAULT_STOR_EN_INVEST_COST
stor_pw_invest_cost(par, s, sp) = haskey(par.storPWInvCost, s) ? par.storPWInvCost[s][sp] : DEFAULT_STOR_PW_INVEST_COST
trans_invest_cost(par, m, n, sp) = haskey(par.transmissionInvCost, (m, n)) ? par.transmissionInvCost[(m, n)][sp] : DEFAULT_TRANS_INVEST_COST

lost_load_cost(par, n, t) = haskey(par.nodeLostLoadCost, n) ? par.nodeLostLoadCost[n][t] : DEFAULT_LOST_LOAD_COST
sload(par, n, t) = haskey(par.sload, n) ? par.sload[n][t] : DEFAULT_LOAD
gen_marginal_cost(par, g, t) = haskey(par.genMargCost, g) ? par.genMargCost[g][t] : DEFAULT_GEN_MARGINAL_COST

# Validation

# Sample the numeric values of a `TimeProfile` at every period of the supplied
# `TimeStructure`.
function _profile_values(p::TimeProfile, periods::TimeStructure)
    out = Float64[]
    for t in periods
        push!(out, float(p[t]))
    end
    return out
end


function _check_scalar!(errs, name, x; min = nothing, max = nothing, allow_nothing = true)
    x === nothing && return allow_nothing ||
        (push!(errs, "$name must not be nothing"); false)
    min !== nothing && x < min && push!(errs, "$name = $(x) is below minimum $(min)")
    max !== nothing && x > max && push!(errs, "$name = $(x) is above maximum $(max)")
end

function _check_float_dict!(errs, name, d::AbstractDict; min = nothing, max = nothing)
    for (k, v) in d
        min !== nothing && v < min && push!(errs, "$name[$(k)] = $(v) is below minimum $(min)")
        max !== nothing && v > max && push!(errs, "$name[$(k)] = $(v) is above maximum $(max)")
    end
end

function _check_profile_dict!(errs, name, d::AbstractDict,
                              periods::Union{Nothing, TimeStructure};
                              min = nothing, max = nothing)
    periods === nothing && return
    for (k, prof) in d
        for v in _profile_values(prof, periods)
            if min !== nothing && v < min
                push!(errs, "$name[$(k)] contains a value $(v) below minimum $(min)")
                break
            end
            if max !== nothing && v > max
                push!(errs, "$name[$(k)] contains a value $(v) above maximum $(max)")
                break
            end
        end
    end
end

function _check_profile_scalar!(errs, name, prof,
                                periods::Union{Nothing, TimeStructure};
                                min = nothing, max = nothing)
    prof === nothing && return
    periods === nothing && return
    for v in _profile_values(prof, periods)
        min !== nothing && v < min &&
            (push!(errs, "$name contains a value $(v) below minimum $(min)"); break)
        max !== nothing && v > max &&
            (push!(errs, "$name contains a value $(v) above maximum $(max)"); break)
    end
end

function _check_keys_in_set!(errs, name, d::AbstractDict, valid_set, label)
    isempty(valid_set) && return
    for k in keys(d)
        k in valid_set || push!(errs, "$name has unknown $label key: $(k)")
    end
end

function _check_tuple_keys_in_sets!(errs, name, d::AbstractDict, valid1, label1, valid2, label2;
                                    allowed_pairs = nothing)
    for k in keys(d)
        a, b = k[1], k[2]
        (!isempty(valid1) && !(a in valid1)) &&
            push!(errs, "$name has unknown $label1 in key $(k): $(a)")
        (!isempty(valid2) && !(b in valid2)) &&
            push!(errs, "$name has unknown $label2 in key $(k): $(b)")
        if allowed_pairs !== nothing && !((a, b) in allowed_pairs)
            push!(errs, "$name key $(k) is not a valid ($label1, $label2) pair")
        end
    end
end

"""
    validate(par::EmpireParams; sets::Union{Nothing, EmpireSets} = nothing,
             periods::Union{Nothing, TimeStructure} = nothing,
             strict::Bool = true)

Validate the values of an [`EmpireParams`](@ref) instance.

The function performs three kinds of checks:

1. Scalar / dictionary value-range checks (always performed):
   - `WACC` and `discountRate` are finite numbers in `[0, 1]` (if set).
   - Efficiencies (`lineEfficiency`, `storageBleedEff`, `storageChargeEff`,
     `storageDischargeEff`) are in `[0, 1]`.
   - Costs, capacities and CO2 quantities are finite and non-negative.
   - Lifetimes are strictly positive.
   - `genRampUpCap` and `genCapAvailType` are in `[0, 1]`.

2. `TimeProfile` value-range checks (only when `periods` is provided):
   Each profile is sampled at every period of the supplied `TimeStructure`
   and the resulting values are checked against the same numeric bounds as
   their non-profile counterparts (e.g. `genEfficiency` and `genCapAvail`
   must lie in `[0, 1]`; all other profiles must be finite and
   non-negative). If `periods` is `nothing`, profile contents are not
   inspected (their keys are still checked when `sets` is given).

3. Index checks (only when `sets` is provided): every dictionary key is
   verified to reference an id that exists in the given `EmpireSets`
   (generators, storages, nodes, transmission types, arcs, etc.).

When `strict = true` (the default) an `ArgumentError` is thrown summarising
all detected issues. When `strict = false` the function returns the vector
of issue messages (empty if everything is valid) and only emits warnings.
"""
function validate(par::EmpireParams; sets::Union{Nothing, EmpireSets} = nothing,
                  periods::Union{Nothing, TimeStructure} = nothing,
                  strict::Bool = true)
    errs = String[]

    # Scalar / financial parameters
    _check_scalar!(errs, "WACC", par.WACC; min = 0.0, max = 1.0)
    _check_scalar!(errs, "discountRate", par.discountRate; min = 0.0, max = 1.0)

    # Float64 dicts: non-negative costs / capacities
    _check_float_dict!(errs, "genVariableOMCost", par.genVariableOMCost; min = 0.0)
    _check_float_dict!(errs, "genRefInitCap", par.genRefInitCap; min = 0.0)
    _check_float_dict!(errs, "genMaxInstalledCapRaw", par.genMaxInstalledCapRaw; min = 0.0)
    _check_float_dict!(errs, "genCO2Content", par.genCO2Content; min = 0.0)

    _check_float_dict!(errs, "genRampUpCap", par.genRampUpCap; min = 0.0, max = 1.0)
    _check_float_dict!(errs, "genCapAvailType", par.genCapAvailType; min = 0.0, max = 1.0)
    _check_float_dict!(errs, "genLifetime", par.genLifetime; min = nextfloat(0.0))

    _check_float_dict!(errs, "transmissionLength", par.transmissionLength; min = 0.0)
    _check_float_dict!(errs, "lineEfficiency", par.lineEfficiency; min = 0.0, max = 1.0)
    _check_float_dict!(errs, "transmissionLifetime", par.transmissionLifetime; min = nextfloat(0.0))

    _check_float_dict!(errs, "storageBleedEff", par.storageBleedEff; min = 0.0, max = 1.0)
    _check_float_dict!(errs, "storageChargeEff", par.storageChargeEff; min = 0.0, max = 1.0)
    _check_float_dict!(errs, "storageDischargeEff", par.storageDischargeEff; min = 0.0, max = 1.0)
    _check_float_dict!(errs, "storagePowToEnergy", par.storagePowToEnergy; min = 0.0)
    _check_float_dict!(errs, "storENMaxInstalledCap", par.storENMaxInstalledCap; min = 0.0)
    _check_float_dict!(errs, "storPWMaxInstalledCap", par.storPWMaxInstalledCap; min = 0.0)
    _check_float_dict!(errs, "storOperationalInit", par.storOperationalInit; min = 0.0, max = 1.0)
    _check_float_dict!(errs, "storageLifetime", par.storageLifetime; min = nextfloat(0.0))

    _check_float_dict!(errs, "maxHydroNode", par.maxHydroNode; min = 0.0)

    # TimeProfile dicts
    for (name, d) in (
        ("genCapitalCost",              par.genCapitalCost),
        ("genFixedOMCost",              par.genFixedOMCost),
        ("genFuelCost",                 par.genFuelCost),
        ("genScaleInitCap",             par.genScaleInitCap),
        ("genInitCap",                  par.genInitCap),
        ("genMaxBuiltCap",              par.genMaxBuiltCap),
        ("genMaxInstalledCap",          par.genMaxInstalledCap),
        ("transmissionInitCap",         par.transmissionInitCap),
        ("transmissionMaxBuiltCap",     par.transmissionMaxBuiltCap),
        ("transmissionMaxInstalledCap", par.transmissionMaxInstalledCap),
        ("transmissionTypeCapitalCost", par.transmissionTypeCapitalCost),
        ("transmissionTypeFixedOMCost", par.transmissionTypeFixedOMCost),
        ("storENCapitalCost",           par.storENCapitalCost),
        ("storENFixedOMCost",           par.storENFixedOMCost),
        ("storENInitCap",               par.storENInitCap),
        ("storENMaxBuiltCap",           par.storENMaxBuiltCap),
        ("storPWCapitalCost",           par.storPWCapitalCost),
        ("storPWFixedOMCost",           par.storPWFixedOMCost),
        ("storPWInitCap",               par.storPWInitCap),
        ("storPWMaxBuiltCap",           par.storPWMaxBuiltCap),
        ("nodeLostLoadCost",            par.nodeLostLoadCost),
        ("sloadAnnualDemand",           par.sloadAnnualDemand),
        ("sloadRaw",                    par.sloadRaw),
        ("sload",                       par.sload),
        ("maxRegHydroGenRaw",           par.maxRegHydroGenRaw),
        ("maxRegHydroGen",              par.maxRegHydroGen),
        ("genInvCost",                  par.genInvCost),
        ("storENInvCost",               par.storENInvCost),
        ("storPWInvCost",               par.storPWInvCost),
        ("transmissionInvCost",         par.transmissionInvCost),
        ("genMargCost",                 par.genMargCost),
    )
        _check_profile_dict!(errs, name, d, periods; min = 0.0)
    end

    # genEfficiency: profile values in [0, 1]
    _check_profile_dict!(errs, "genEfficiency", par.genEfficiency, periods; min = 0.0, max = 1.0)
    # genCapAvail: profile values in [0, 1]
    _check_profile_dict!(errs, "genCapAvail", par.genCapAvail, periods; min = 0.0, max = 1.0)

    # Scalar TimeProfiles
    _check_profile_scalar!(errs, "CCSCostTSVariable", par.CCSCostTSVariable, periods; min = 0.0)
    _check_profile_scalar!(errs, "CO2cap", par.CO2cap, periods; min = 0.0)
    _check_profile_scalar!(errs, "CO2price", par.CO2price, periods; min = 0.0)

    # Index checks (only if a set is provided)
    if sets !== nothing
        gset  = Set(generators(sets))
        sset  = Set(storages(sets))
        nset  = Set(nodes(sets))
        ttset = Set(transmission_types(sets))
        arcset = Set(arcs(sets))
        ng_pairs = Set(node_generators(sets))
        ns_pairs = Set(node_storages(sets))

        # String-keyed dicts indexed by generator
        for (name, d) in (
            ("genCapitalCost",    par.genCapitalCost),
            ("genFixedOMCost",    par.genFixedOMCost),
            ("genVariableOMCost", par.genVariableOMCost),
            ("genFuelCost",       par.genFuelCost),
            ("genEfficiency",     par.genEfficiency),
            ("genScaleInitCap",   par.genScaleInitCap),
            ("genRampUpCap",      par.genRampUpCap),
            ("genCapAvailType",   par.genCapAvailType),
            ("genCO2Content",     par.genCO2Content),
            ("genLifetime",       par.genLifetime),
            ("genInvCost",        par.genInvCost),
            ("genMargCost",       par.genMargCost),
        )
            _check_keys_in_set!(errs, name, d, gset, "generator")
        end

        # String-keyed dicts indexed by storage
        for (name, d) in (
            ("storageBleedEff",     par.storageBleedEff),
            ("storageChargeEff",    par.storageChargeEff),
            ("storageDischargeEff", par.storageDischargeEff),
            ("storagePowToEnergy",  par.storagePowToEnergy),
            ("storENCapitalCost",   par.storENCapitalCost),
            ("storENFixedOMCost",   par.storENFixedOMCost),
            ("storOperationalInit", par.storOperationalInit),
            ("storPWCapitalCost",   par.storPWCapitalCost),
            ("storPWFixedOMCost",   par.storPWFixedOMCost),
            ("storageLifetime",     par.storageLifetime),
            ("storENInvCost",       par.storENInvCost),
            ("storPWInvCost",       par.storPWInvCost),
        )
            _check_keys_in_set!(errs, name, d, sset, "storage")
        end

        # String-keyed dicts indexed by node
        for (name, d) in (
            ("nodeLostLoadCost",  par.nodeLostLoadCost),
            ("sloadAnnualDemand", par.sloadAnnualDemand),
            ("maxHydroNode",      par.maxHydroNode),
            ("sloadRaw",          par.sloadRaw),
            ("sload",             par.sload),
            ("maxRegHydroGenRaw", par.maxRegHydroGenRaw),
            ("maxRegHydroGen",    par.maxRegHydroGen),
        )
            _check_keys_in_set!(errs, name, d, nset, "node")
        end

        # String-keyed dicts indexed by transmission type
        for (name, d) in (
            ("transmissionTypeCapitalCost", par.transmissionTypeCapitalCost),
            ("transmissionTypeFixedOMCost", par.transmissionTypeFixedOMCost),
        )
            _check_keys_in_set!(errs, name, d, ttset, "transmission type")
        end

        # Tuple{node, generator} keyed dicts
        for (name, d) in (
            ("genRefInitCap",         par.genRefInitCap),
            ("genInitCap",            par.genInitCap),
            ("genMaxBuiltCap",        par.genMaxBuiltCap),
            ("genMaxInstalledCapRaw", par.genMaxInstalledCapRaw),
            ("genMaxInstalledCap",    par.genMaxInstalledCap),
            ("genCapAvail",           par.genCapAvail),
        )
            _check_tuple_keys_in_sets!(errs, name, d, nset, "node", gset, "generator";
                                       allowed_pairs = ng_pairs)
        end

        # Tuple{node, storage} keyed dicts
        for (name, d) in (
            ("storENInitCap",       par.storENInitCap),
            ("storENMaxBuiltCap",   par.storENMaxBuiltCap),
            ("storENMaxInstalledCap", par.storENMaxInstalledCap),
            ("storPWInitCap",       par.storPWInitCap),
            ("storPWMaxBuiltCap",   par.storPWMaxBuiltCap),
            ("storPWMaxInstalledCap", par.storPWMaxInstalledCap),
        )
            _check_tuple_keys_in_sets!(errs, name, d, nset, "node", sset, "storage";
                                       allowed_pairs = ns_pairs)
        end

        # Tuple{node, node} keyed dicts (arcs)
        for (name, d) in (
            ("transmissionInitCap",         par.transmissionInitCap),
            ("transmissionMaxBuiltCap",     par.transmissionMaxBuiltCap),
            ("transmissionMaxInstalledCap", par.transmissionMaxInstalledCap),
            ("transmissionLength",          par.transmissionLength),
            ("lineEfficiency",              par.lineEfficiency),
            ("transmissionLifetime",        par.transmissionLifetime),
            ("transmissionInvCost",         par.transmissionInvCost),
        )
            _check_tuple_keys_in_sets!(errs, name, d, nset, "node", nset, "node";
                                       allowed_pairs = arcset)
        end
    end

    if !isempty(errs)
        msg = "EmpireParams validation found $(length(errs)) issue(s):\n  - " *
              join(errs, "\n  - ")
        if strict
            throw(ArgumentError(msg))
        else
            @warn msg
        end
    end

    return strict ? par : errs
end
