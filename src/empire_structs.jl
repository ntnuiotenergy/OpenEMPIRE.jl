const NaturalGasTerminalPeriod = Tuple{String, String, Int}
const NaturalGasTerminalScenario = Tuple{String, String, Int, Int}
const NaturalGasNodePeriod = Tuple{String, Int}

"""
    NaturalGasParams

Numeric natural-gas inputs. The defaults reproduce InternalEMPIRE's fixed
conversion and storage assumptions; all table-backed fields default empty.
"""
Base.@kwdef mutable struct NaturalGasParams
    pipelineCapacity::Dict{Tuple{String, String}, Float64} =
        Dict{Tuple{String, String}, Float64}()
    pipelinePowerDemandPerTon::Float64 = 0.0
    terminalCost::Dict{NaturalGasTerminalScenario, Float64} =
        Dict{NaturalGasTerminalScenario, Float64}()
    terminalCapacity::Dict{NaturalGasTerminalPeriod, Float64} =
        Dict{NaturalGasTerminalPeriod, Float64}()
    storageCapacity::Dict{String, Float64} = Dict{String, Float64}()
    reserves::Dict{String, Float64} = Dict{String, Float64}()
    transportDemand::Dict{NaturalGasNodePeriod, Float64} =
        Dict{NaturalGasNodePeriod, Float64}()
    transportCurtailCost::Float64 = 10000.0
    mwhPerTon::Float64 = 13.9
    storageInitialFraction::Float64 = 0.5
    storageChargeEfficiency::Float64 = 1.0
    storageDischargeEfficiency::Float64 = 1.0
    weatherScenarioCount::Int = 1
    gasScenarioCount::Int = 1
end

const HydrogenPlantPeriod = Tuple{String, Int}
const HydrogenNodeStorage = Tuple{String, String}
const HydrogenNodeTerminalPeriod = Tuple{String, String, Int}
const HydrogenNodePeriod = Tuple{String, Int}

const IndustryPlantPeriod = Tuple{String, Int}
const IndustryNodePlant = Tuple{String, String}
const IndustryNodePeriod = Tuple{String, Int}

"""Typed deterministic steel, cement, ammonia, and refinery parameters."""
Base.@kwdef mutable struct IndustryParams
    steelLifetime::Dict{String, Float64} = Dict{String, Float64}()
    steelInitialCapacity::Dict{IndustryNodePlant, Float64} = Dict{IndustryNodePlant, Float64}()
    steelRetirementFactor::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    steelCapitalCost::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    steelFixedOMCost::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    steelInvestmentCost::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    steelVariableOMCost::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    steelCoalConsumption::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    steelHydrogenConsumption::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    steelBiomassConsumption::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    steelOilConsumption::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    steelElectricityConsumption::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    steelCO2Emissions::Dict{String, Float64} = Dict{String, Float64}()
    steelCO2Captured::Dict{String, Float64} = Dict{String, Float64}()
    steelYearlyProduction::Dict{IndustryNodePeriod, Float64} = Dict{IndustryNodePeriod, Float64}()
    cementLifetime::Dict{String, Float64} = Dict{String, Float64}()
    cementInitialCapacity::Dict{IndustryNodePlant, Float64} = Dict{IndustryNodePlant, Float64}()
    cementRetirementFactor::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    cementCapitalCost::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    cementFixedOMCost::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    cementInvestmentCost::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    cementFuelConsumption::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    cementCO2CaptureRate::Dict{String, Float64} = Dict{String, Float64}()
    cementElectricityConsumption::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    cementYearlyProduction::Dict{String, Float64} = Dict{String, Float64}()
    ammoniaLifetime::Dict{String, Float64} = Dict{String, Float64}()
    ammoniaInitialCapacity::Dict{IndustryNodePlant, Float64} = Dict{IndustryNodePlant, Float64}()
    ammoniaRetirementFactor::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    ammoniaCapitalCost::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    ammoniaFixedOMCost::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    ammoniaInvestmentCost::Dict{IndustryPlantPeriod, Float64} = Dict{IndustryPlantPeriod, Float64}()
    ammoniaFeedstockConsumption::Dict{String, Float64} = Dict{String, Float64}()
    ammoniaElectricityConsumption::Dict{String, Float64} = Dict{String, Float64}()
    ammoniaYearlyProduction::Dict{IndustryNodePeriod, Float64} = Dict{IndustryNodePeriod, Float64}()
    refineryYearlyProduction::Dict{IndustryNodePeriod, Float64} = Dict{IndustryNodePeriod, Float64}()
    availableBioEnergy::Dict{Int, Float64} = Dict{Int, Float64}()
    industryShedCost::Float64 = 100000.0
    refineryHydrogenConsumption::Float64 = 0.0
    refineryHeatConsumption::Float64 = 0.0
    rampFractionPerHour::Float64 = 0.1
    maximumScrapShare::Float64 = 0.45
    hoursPerYear::Float64 = 8760.0
    oilShedCost::Float64 = 1.0e6
end

"""Typed deterministic Hydrogen and CO₂ input parameters."""
Base.@kwdef mutable struct HydrogenParams
    electrolyzerCapitalCost::Dict{Int, Float64} = Dict{Int, Float64}()
    electrolyzerFixedOMCost::Dict{Int, Float64} = Dict{Int, Float64}()
    electrolyzerPowerUse::Dict{Int, Float64} = Dict{Int, Float64}()
    electrolyzerLifetime::Float64 = 0.0
    reformerCapitalCost::Dict{HydrogenPlantPeriod, Float64} = Dict{HydrogenPlantPeriod, Float64}()
    reformerFixedOMCost::Dict{HydrogenPlantPeriod, Float64} = Dict{HydrogenPlantPeriod, Float64}()
    reformerVariableOMCost::Dict{HydrogenPlantPeriod, Float64} = Dict{HydrogenPlantPeriod, Float64}()
    reformerEfficiency::Dict{HydrogenPlantPeriod, Float64} = Dict{HydrogenPlantPeriod, Float64}()
    reformerElectricityUse::Dict{HydrogenPlantPeriod, Float64} = Dict{HydrogenPlantPeriod, Float64}()
    reformerEmissionFactor::Dict{HydrogenPlantPeriod, Float64} = Dict{HydrogenPlantPeriod, Float64}()
    reformerCO2CaptureFactor::Dict{HydrogenPlantPeriod, Float64} = Dict{HydrogenPlantPeriod, Float64}()
    reformerLifetime::Dict{String, Float64} = Dict{String, Float64}()
    pipelineCapitalCost::Dict{Int, Float64} = Dict{Int, Float64}()
    pipelineOMCostPerKM::Dict{Int, Float64} = Dict{Int, Float64}()
    pipelineCompressorPowerUsage::Float64 = 0.0
    storageCapitalCost::Dict{HydrogenPlantPeriod, Float64} = Dict{HydrogenPlantPeriod, Float64}()
    storageFixedOMCost::Dict{HydrogenPlantPeriod, Float64} = Dict{HydrogenPlantPeriod, Float64}()
    storageLifetime::Dict{String, Float64} = Dict{String, Float64}()
    storageMaxCapacity::Dict{HydrogenNodeStorage, Float64} = Dict{HydrogenNodeStorage, Float64}()
    terminalInitialCapacity::Dict{HydrogenNodeTerminalPeriod, Float64} = Dict{HydrogenNodeTerminalPeriod, Float64}()
    terminalCapitalCost::Dict{HydrogenNodeTerminalPeriod, Float64} = Dict{HydrogenNodeTerminalPeriod, Float64}()
    terminalFixedOMCost::Dict{HydrogenNodeTerminalPeriod, Float64} = Dict{HydrogenNodeTerminalPeriod, Float64}()
    terminalPrice::Dict{HydrogenNodeTerminalPeriod, Float64} = Dict{HydrogenNodeTerminalPeriod, Float64}()
    terminalLifetime::Dict{String, Float64} = Dict{String, Float64}()
    electricityTransportDemand::Dict{HydrogenNodePeriod, Float64} = Dict{HydrogenNodePeriod, Float64}()
    hydrogenTransportDemand::Dict{HydrogenNodePeriod, Float64} = Dict{HydrogenNodePeriod, Float64}()
    generatorCO2Captured::Dict{String, Float64} = Dict{String, Float64}()
    co2StorageMaxCapacity::Dict{HydrogenNodePeriod, Float64} = Dict{HydrogenNodePeriod, Float64}()
    co2MaxSequestrationCapacity::Dict{String, Float64} = Dict{String, Float64}()
    co2StorageSiteCapitalCost::Dict{String, Float64} = Dict{String, Float64}()
    co2StorageSiteFixedOMCost::Dict{String, Float64} = Dict{String, Float64}()
    co2PipelineCapitalCost::Float64 = 0.0
    co2PipelineFixedOMCost::Float64 = 0.0
    co2PipelineElectricityUsage::Float64 = 0.0
    co2PipelineLifetime::Float64 = 0.0
    hydrogenMWhPerTon::Float64 = 33.3
    storageInitialFraction::Float64 = 0.5
    storageCompressionMWhPerTon::Float64 = 0.333
    pipelineCompressorStaticMWhPerTon::Float64 = 1.0
    pipelineLifetime::Float64 = 40.0
    pipelineLeakageFractionPerKM::Float64 = 5e-6
    reformerRampFractionPerHour::Float64 = 0.1
    repurposeCostFactor::Float64 = 0.25
    repurposeEnergyFlowFactor::Float64 = 0.8
    terminalEURPerKgToEURPerTon::Float64 = 1000.0
    hoursPerYear::Float64 = 8760.0
end

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
    genCapitalCost::Dict{String, TimeProfile}                    = Dict{String, TimeProfile}()
    genFixedOMCost::Dict{String, TimeProfile}                    = Dict{String, TimeProfile}()
    genVariableOMCost::Dict{String, Float64}                     = Dict{String, Float64}()
    genFuelCost::Dict{String, TimeProfile}                       = Dict{String, TimeProfile}()
    CCSCostTSVariable::Union{Nothing, TimeProfile}               = nothing
    # CO2 transport-and-storage cost charged on CCS generator *investment*, in
    # EUR per tCO2 of annual capture capability. `nothing` keeps the historical
    # hardcoded default (see `ccs_cost_fixed`); supply Generator/CCSCostTSFixed.csv
    # to override, including with 0.0 to disable the charge entirely.
    CCSCostTSFixed::Union{Nothing, Float64}                      = nothing
    genEfficiency::Dict{String, TimeProfile}                     = Dict{String, TimeProfile}()
    genRefInitCap::Dict{Tuple{String, String}, Float64}          = Dict{Tuple{String, String}, Float64}()
    genScaleInitCap::Dict{String, TimeProfile}                   = Dict{String, TimeProfile}()
    genInitCap::Dict{Tuple{String, String}, TimeProfile}         = Dict{Tuple{String, String}, TimeProfile}()
    genMaxBuiltCap::Dict{Tuple{String, String}, TimeProfile}     = Dict{Tuple{String, String}, TimeProfile}()
    genMaxInstalledCapRaw::Dict{Tuple{String, String}, Float64}  = Dict{Tuple{String, String}, Float64}()
    genMaxInstalledCap::Dict{Tuple{String, String}, TimeProfile} = Dict{Tuple{String, String}, TimeProfile}()
    genRampUpCap::Dict{String, Float64}                          = Dict{String, Float64}()
    genCapAvailType::Dict{String, Float64}                       = Dict{String, Float64}()
    genCO2Content::Dict{String, Float64}                         = Dict{String, Float64}()
    genLifetime::Dict{String, Float64}                           = Dict{String, Float64}()

    # Transmission inputs from file
    transmissionInitCap::Dict{Tuple{String, String}, TimeProfile}         = Dict{Tuple{String, String}, TimeProfile}()
    transmissionMaxBuiltCap::Dict{Tuple{String, String}, TimeProfile}     = Dict{Tuple{String, String}, TimeProfile}()
    transmissionMaxInstalledCap::Dict{Tuple{String, String}, TimeProfile} = Dict{Tuple{String, String}, TimeProfile}()
    transmissionLength::Dict{Tuple{String, String}, Float64}              = Dict{Tuple{String, String}, Float64}()
    transmissionTypeCapitalCost::Dict{String, TimeProfile}                = Dict{String, TimeProfile}()
    transmissionTypeFixedOMCost::Dict{String, TimeProfile}                = Dict{String, TimeProfile}()
    lineEfficiency::Dict{Tuple{String, String}, Float64}                  = Dict{Tuple{String, String}, Float64}()
    transmissionLifetime::Dict{Tuple{String, String}, Float64}            = Dict{Tuple{String, String}, Float64}()

    # Storage inputs from file
    storageBleedEff::Dict{String, Float64}                      = Dict{String, Float64}()
    storageChargeEff::Dict{String, Float64}                     = Dict{String, Float64}()
    storageDischargeEff::Dict{String, Float64}                  = Dict{String, Float64}()
    storageDiscToCharRatio::Dict{String, Float64}               = Dict{String, Float64}()
    storagePowToEnergy::Dict{String, Float64}                   = Dict{String, Float64}()
    storENCapitalCost::Dict{String, TimeProfile}                = Dict{String, TimeProfile}()
    storENFixedOMCost::Dict{String, TimeProfile}                = Dict{String, TimeProfile}()
    storENInitCap::Dict{Tuple{String, String}, TimeProfile}     = Dict{Tuple{String, String}, TimeProfile}()
    storENMaxBuiltCap::Dict{Tuple{String, String}, TimeProfile} = Dict{Tuple{String, String}, TimeProfile}()
    storENMaxInstalledCap::Dict{Tuple{String, String}, Float64} = Dict{Tuple{String, String}, Float64}()
    storOperationalInit::Dict{String, Float64}                  = Dict{String, Float64}()
    storPWCapitalCost::Dict{String, TimeProfile}                = Dict{String, TimeProfile}()
    storPWFixedOMCost::Dict{String, TimeProfile}                = Dict{String, TimeProfile}()
    storPWInitCap::Dict{Tuple{String, String}, TimeProfile}     = Dict{Tuple{String, String}, TimeProfile}()
    storPWMaxBuiltCap::Dict{Tuple{String, String}, TimeProfile} = Dict{Tuple{String, String}, TimeProfile}()
    storPWMaxInstalledCap::Dict{Tuple{String, String}, Float64} = Dict{Tuple{String, String}, Float64}()
    storageLifetime::Dict{String, Float64}                      = Dict{String, Float64}()

    # Node inputs from file
    nodeLostLoadCost::Dict{String, TimeProfile}  = Dict{String, TimeProfile}()
    sloadAnnualDemand::Dict{String, TimeProfile} = Dict{String, TimeProfile}()
    maxHydroNode::Dict{String, Float64}          = Dict{String, Float64}()

    # General parameters from file
    CO2cap::Union{Nothing, TimeProfile}   = nothing
    CO2price::Union{Nothing, TimeProfile} = nothing
    seasonNames::Vector{String}           = String[]
    regularSeasonCount::Int               = 0

    # Stochastic parameters
    sloadRaw::Dict{String, TimeProfile}                   = Dict{String, TimeProfile}()
    sload::Dict{String, TimeProfile}                      = Dict{String, TimeProfile}()
    genCapAvail::Dict{Tuple{String, String}, TimeProfile} = Dict{Tuple{String, String}, TimeProfile}()
    maxRegHydroGenRaw::Dict{String, TimeProfile}          = Dict{String, TimeProfile}()
    maxRegHydroGen::Dict{String, TimeProfile}             = Dict{String, TimeProfile}()

    # Processed parameters
    genInvCost::Dict{String, TimeProfile}                         = Dict{String, TimeProfile}()
    storENInvCost::Dict{String, TimeProfile}                      = Dict{String, TimeProfile}()
    storPWInvCost::Dict{String, TimeProfile}                      = Dict{String, TimeProfile}()
    transmissionInvCost::Dict{Tuple{String, String}, TimeProfile} = Dict{Tuple{String, String}, TimeProfile}()
    genMargCost::Dict{String, TimeProfile}                        = Dict{String, TimeProfile}()

    # Optional sector modules
    NaturalGas::NaturalGasParams = NaturalGasParams()
    Hydrogen::HydrogenParams = HydrogenParams()
    Industry::IndustryParams = IndustryParams()
end

# Default values used by the accessor helpers below.
#
# Whenever a parameter is missing from its underlying `Dict` (i.e. the model
# data does not specify a value for the given generator / storage / node /
# arc), these constants are returned by the corresponding accessor.

# Loads / generation quantities default to zero (no demand, no production)
const DEFAULT_LOAD          = 0.0
const DEFAULT_MAX_HYDRO_GEN = 0.0

# Initial installed capacities default to zero
const DEFAULT_GEN_INIT_CAP     = 0.0
const DEFAULT_STOR_EN_INIT_CAP = 0.0
const DEFAULT_STOR_PW_INIT_CAP = 0.0
const DEFAULT_TRANS_INIT_CAP   = 0.0

# Build / installed capacity limits. Defaults mirror the Python formulation:
# storage build cap defaults to 500000 MW (Param default in empire.py) and the
# storage installed cap defaults to 0.0 (storENMaxInstalledCapRaw/storPWMaxInstalledCapRaw
# default 0.0 -> a storage absent from the cap data is NOT buildable, e.g. the
# Finland/Macedonia HydroPumpStorage entries present in StoragesOfNode). Returning
# `nothing` (no limit) here previously let Julia build storage that Python forbids.
const DEFAULT_GEN_MAX_BUILD_CAP    = 500000.0
const DEFAULT_GEN_MAX_INST_CAP_RAW = 0.0
const DEFAULT_MAX_BUILD_CAP        = 500000.0
const DEFAULT_MAX_INST_CAP         = 0.0
const DEFAULT_TRANS_MAX_BUILD      = nothing
# Pyomo's `transmissionMaxBuiltCap` Param default (base EMPIRE, `empire.py:255`).
# Used only to fill periods that a corridor's CSV rows do not cover, mirroring
# Pyomo's per-cell fallback. Whole-corridor absence keeps `DEFAULT_TRANS_MAX_BUILD`
# (no constraint) for now - see the tracking notes on aligning that with Pyomo.
const PYOMO_DEFAULT_TRANS_MAX_BUILD_CAP = 20000.0
const DEFAULT_TRANS_MAX_INST       = nothing
const DEFAULT_MAX_HYDRO_NODE       = nothing

# Ramp-up cap for a thermal generator missing from genRampUpCap data defaults to 0.0,
# matching Python (`genRampUpCap = Param(model.ThermalGenerators, default=0.0)` in empire.py).
# A missing entry therefore forbids hour-to-hour ramp-up within a season (genOp[h] <= genOp[h-1]),
# rather than leaving the generator unconstrained. This matters for europe_v51, where
# `LigniteCCSsup` is in ThermalGenerators but absent from genRampUpCap.csv (the file duplicates
# `LigniteCCSadv` and omits `LigniteCCSsup`); a 1.0 default left it effectively unrampable-limited
# in Julia while Python pinned it to 0.0.
const DEFAULT_RAMPUP_CAP                 = 0.0
# Efficiencies / availability factors default to 1.0 (lossless / fully available)
const DEFAULT_BLEED_EFF                  = 1.0
const DEFAULT_CHARGE_EFF                 = 1.0
const DEFAULT_DISCHARGE_EFF              = 1.0
const DEFAULT_STORAGE_DISC_TO_CHAR_RATIO = 1.0
const DEFAULT_LINE_EFF                   = 1.0
const DEFAULT_POWER_TO_ENERGY            = 1.0

# Operational initial state of storages defaults to empty
const DEFAULT_STORAGE_INIT = 0.0

# Lifetimes default to 40 years
const DEFAULT_GEN_LIFETIME     = 40
const DEFAULT_STORAGE_LIFETIME = 40
const DEFAULT_TRANS_LIFETIME   = 40

# Investment / marginal costs default to zero
const DEFAULT_GEN_INVEST_COST     = 0.0
const DEFAULT_STOR_EN_INVEST_COST = 0.0
const DEFAULT_STOR_PW_INVEST_COST = 0.0
const DEFAULT_TRANS_INVEST_COST   = 0.0
const DEFAULT_GEN_MARGINAL_COST   = 0.0

# Penalty cost for unserved load (high so it is rarely optimal to shed load).
# Must match Python's `nodeLostLoadCost = Param(model.Node, model.Period, default=22000.0)`
# (empire.py). europe_v51's nodeLostLoadCost.csv lists only 35 of 49 nodes (period 1 only);
# the 14 missing nodes fall back to this default. A 1000.0 default made shedding ~22x cheaper
# than Python at those nodes, so Julia shed load instead of building generation (~36e9 less
# generator investment) and reached a spuriously cheaper optimum — the bulk of the long-horizon
# europe_v51 objective gap.
const DEFAULT_LOST_LOAD_COST = 22000.0

# Helper functions to get parameter values with default fallbacks, the model should
# only use these functions to access parameter values

# Financial properties
wacc(par) = par.WACC
discount_rate(par) = par.discountRate

# Emission / CCS properties
co2_price(par, sp) = par.CO2price === nothing ? 0.0 : par.CO2price[sp]
co2_cap(par, sp) = par.CO2cap === nothing ? nothing : par.CO2cap[sp]
co2_content(par, g) = get(par.genCO2Content, g, 0.0)
ccs_cost_variable(par, sp) = par.CCSCostTSVariable === nothing ? 0.0 : par.CCSCostTSVariable[sp]

"""
    DEFAULT_CCS_COST_FIXED

CO2 transport-and-storage cost charged on CCS generator investment, EUR/tCO2.

Matches the value InternalEMPIRE declares at `empire.py:461`
(`CCSCostTSFix = Param(initialize=1149873.72) #NB! Hard-coded`). Note that the
reference has that declaration, and its variable counterpart at `empire.py:462`,
**commented out**, so InternalEMPIRE charges neither. OpenEMPIRE.jl charges both,
which is a documented difference rather than an accident: base OpenEMPIRE charges
CCS transport-and-storage costs, and this port follows the base. Whether these
costs should apply is a modelling decision for the dataset owner; both values are
data-driven and can be zeroed per dataset.
"""
const DEFAULT_CCS_COST_FIXED = 1149873.72

ccs_cost_fixed(par) = par.CCSCostTSFixed === nothing ? DEFAULT_CCS_COST_FIXED : par.CCSCostTSFixed

# General properties
load(par, n, t) = haskey(par.sload, n) ? par.sload[n][t] : DEFAULT_LOAD
season_name(par, representative_index::Integer) =
    1 <= representative_index <= length(par.seasonNames) ? par.seasonNames[representative_index] : ""
regular_season_count(par, representative_count::Integer) =
    par.regularSeasonCount > 0 ? min(par.regularSeasonCount, representative_count) : representative_count

# Generator properties
gencap_avail(par, n, g, t) =
    haskey(par.genCapAvail, (n, g)) ? par.genCapAvail[(n, g)][t] : par.genCapAvailType[g]
rampup_cap(par, g) = get(par.genRampUpCap, g, DEFAULT_RAMPUP_CAP)
max_build_cap(par, n, gt, sp) =
    haskey(par.genMaxBuiltCap, (n, gt)) ? par.genMaxBuiltCap[(n, gt)][sp] : DEFAULT_GEN_MAX_BUILD_CAP
max_inst_cap(par, n, gt, sp) =
    haskey(par.genMaxInstalledCap, (n, gt)) ? par.genMaxInstalledCap[(n, gt)][sp] : DEFAULT_GEN_MAX_INST_CAP_RAW
gen_lifetime(par, g) = get(par.genLifetime, g, DEFAULT_GEN_LIFETIME)
gencap_init(par, n, g, sp) = (n, g) in keys(par.genInitCap) ? par.genInitCap[(n, g)][sp] : DEFAULT_GEN_INIT_CAP
max_hydro_gen(par, n, sc) = haskey(par.maxRegHydroGen, n) ? par.maxRegHydroGen[n][sc] : DEFAULT_MAX_HYDRO_GEN
max_hydro_node(par, n) = get(par.maxHydroNode, n, DEFAULT_MAX_HYDRO_NODE)

# Storage properties
bleed_eff(par, s) = get(par.storageBleedEff, s, DEFAULT_BLEED_EFF)
charge_eff(par, s) = get(par.storageChargeEff, s, DEFAULT_CHARGE_EFF)
discharge_eff(par, s) = get(par.storageDischargeEff, s, DEFAULT_DISCHARGE_EFF)
storage_disc_to_char_ratio(par, s) =
    get(par.storageDiscToCharRatio, s, DEFAULT_STORAGE_DISC_TO_CHAR_RATIO)
storage_init(par, s) = get(par.storOperationalInit, s, DEFAULT_STORAGE_INIT)
lifetime_storage(par, s) = get(par.storageLifetime, s, DEFAULT_STORAGE_LIFETIME)
stor_cap_init_en(par, n, s, sp) = haskey(par.storENInitCap, (n, s)) ? par.storENInitCap[(n, s)][sp] : DEFAULT_STOR_EN_INIT_CAP
stor_cap_init_pow(par, n, s, sp) = haskey(par.storPWInitCap, (n, s)) ? par.storPWInitCap[(n, s)][sp] : DEFAULT_STOR_PW_INIT_CAP
stor_en_max_build_cap(par, n, s, sp) =
    haskey(par.storENMaxBuiltCap, (n, s)) ? par.storENMaxBuiltCap[(n, s)][sp] : DEFAULT_MAX_BUILD_CAP
stor_pw_max_build_cap(par, n, s, sp) =
    haskey(par.storPWMaxBuiltCap, (n, s)) ? par.storPWMaxBuiltCap[(n, s)][sp] : DEFAULT_MAX_BUILD_CAP
stor_en_max_inst_cap(par, n, s, sp) =
    haskey(par.storENMaxInstalledCap, (n, s)) ? par.storENMaxInstalledCap[(n, s)] : DEFAULT_MAX_INST_CAP
stor_pw_max_inst_cap(par, n, s, sp) =
    haskey(par.storPWMaxInstalledCap, (n, s)) ? par.storPWMaxInstalledCap[(n, s)] : DEFAULT_MAX_INST_CAP
power_to_energy(par, s) = get(par.storagePowToEnergy, s, DEFAULT_POWER_TO_ENERGY)

# Transmission properties
#
# A transmission corridor is a single physical line whose data (capacity, cost,
# lifetime, efficiency, length) is symmetric in its two flow directions, but each
# value is stored under a single (from, to) orientation in the CSV input. The model
# uses one capacity variable and one investment cost per corridor, indexed by the
# canonical orientation `bidir_arcs` assigns via `is_bidir` (min, max) — which need
# not match the orientation present in the data. Every per-corridor accessor must
# therefore resolve the value from either stored orientation; otherwise the canonical
# key misses, the `nothing`/default leaks in, and (for caps) the constraint is silently
# skipped or (for cost) the line becomes free. Python avoids this entirely by collapsing
# both links into one orientation-independent BidirectionalArc; see
# DIAGNOSIS_parity_test_dataset.md.
_corridor_profile(dict, m, n) =
    haskey(dict, (m, n)) ? dict[(m, n)] : get(dict, (n, m), nothing)

function trans_cap_init(par, m, n, sp)
    p = _corridor_profile(par.transmissionInitCap, m, n)
    return p === nothing ? DEFAULT_TRANS_INIT_CAP : p[sp]
end
trans_lifetime(par, m, n) =
    haskey(par.transmissionLifetime, (m, n)) ? par.transmissionLifetime[(m, n)] :
    get(par.transmissionLifetime, (n, m), DEFAULT_TRANS_LIFETIME)
trans_max_build_cap(par, m, n, sp) =
    (p = _corridor_profile(par.transmissionMaxBuiltCap, m, n)) === nothing ? DEFAULT_TRANS_MAX_BUILD : p[sp]
trans_max_inst_cap(par, m, n, sp) =
    (p = _corridor_profile(par.transmissionMaxInstalledCap, m, n)) === nothing ? DEFAULT_TRANS_MAX_INST : p[sp]
line_eff(par, m, n) =
    haskey(par.lineEfficiency, (m, n)) ? par.lineEfficiency[(m, n)] :
    get(par.lineEfficiency, (n, m), DEFAULT_LINE_EFF)

# Cost properties
gen_invest_cost(par, g, sp) = haskey(par.genInvCost, g) ? par.genInvCost[g][sp] : DEFAULT_GEN_INVEST_COST
stor_en_invest_cost(par, s, sp) = haskey(par.storENInvCost, s) ? par.storENInvCost[s][sp] : DEFAULT_STOR_EN_INVEST_COST
stor_pw_invest_cost(par, s, sp) = haskey(par.storPWInvCost, s) ? par.storPWInvCost[s][sp] : DEFAULT_STOR_PW_INVEST_COST
function trans_invest_cost(par, m, n, sp)
    p = _corridor_profile(par.transmissionInvCost, m, n)
    return p === nothing ? DEFAULT_TRANS_INVEST_COST : p[sp]
end

lost_load_cost(par, n, t) = haskey(par.nodeLostLoadCost, n) ? par.nodeLostLoadCost[n][t] : DEFAULT_LOST_LOAD_COST
sload(par, n, t) = haskey(par.sload, n) ? par.sload[n][t] : DEFAULT_LOAD
gen_marginal_cost(par, g, t) = haskey(par.genMargCost, g) ? par.genMargCost[g][t] : DEFAULT_GEN_MARGINAL_COST
natural_gas_pipeline_capacity(par::EmpireParams, from, to) =
    get(par.NaturalGas.pipelineCapacity, (from, to), 0.0)
natural_gas_storage_capacity(par::EmpireParams, node) =
    get(par.NaturalGas.storageCapacity, node, 0.0)
natural_gas_reserves(par::EmpireParams, node) =
    get(par.NaturalGas.reserves, node, 0.0)
natural_gas_terminal_capacity(par::EmpireParams, node, terminal, period::Integer) =
    get(par.NaturalGas.terminalCapacity, (node, terminal, Int(period)), 0.0)
natural_gas_terminal_cost(
    par::EmpireParams,
    node,
    terminal,
    period::Integer,
    gas_scenario::Integer,
) = get(
    par.NaturalGas.terminalCost,
    (node, terminal, Int(period), Int(gas_scenario)),
    99999.0,
)
natural_gas_transport_demand(par::EmpireParams, node, period::Integer) =
    get(par.NaturalGas.transportDemand, (node, Int(period)), 0.0)

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
    return max !== nothing && x > max && push!(errs, "$name = $(x) is above maximum $(max)")
end

function _check_float_dict!(errs, name, d::AbstractDict; min = nothing, max = nothing)
    for (k, v) in d
        min !== nothing && v < min && push!(errs, "$name[$(k)] = $(v) is below minimum $(min)")
        max !== nothing && v > max && push!(errs, "$name[$(k)] = $(v) is above maximum $(max)")
    end
    return
end

function _check_profile_dict!(
        errs, name, d::AbstractDict,
        periods::Union{Nothing, TimeStructure};
        min = nothing, max = nothing
    )
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
    return
end

function _check_profile_scalar!(
        errs, name, prof,
        periods::Union{Nothing, TimeStructure};
        min = nothing, max = nothing
    )
    prof === nothing && return
    periods === nothing && return
    for v in _profile_values(prof, periods)
        min !== nothing && v < min &&
            (push!(errs, "$name contains a value $(v) below minimum $(min)"); break)
        max !== nothing && v > max &&
            (push!(errs, "$name contains a value $(v) above maximum $(max)"); break)
    end
    return
end

function _check_keys_in_set!(errs, name, d::AbstractDict, valid_set, label)
    isempty(valid_set) && return
    for k in keys(d)
        k in valid_set || push!(errs, "$name has unknown $label key: $(k)")
    end
    return
end

function _check_tuple_keys_in_sets!(
        errs, name, d::AbstractDict, valid1, label1, valid2, label2;
        allowed_pairs = nothing
    )
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
    return
end

function _check_natural_gas_params!(
    errs::Vector{String},
    par::EmpireParams,
    sets::Union{Nothing, EmpireSets},
    periods::Union{Nothing, TimeStructure},
)
    gas = par.NaturalGas
    for (name, value) in (
        ("pipelinePowerDemandPerTon", gas.pipelinePowerDemandPerTon),
        ("transportCurtailCost", gas.transportCurtailCost),
        ("mwhPerTon", gas.mwhPerTon),
        ("storageInitialFraction", gas.storageInitialFraction),
        ("storageChargeEfficiency", gas.storageChargeEfficiency),
        ("storageDischargeEfficiency", gas.storageDischargeEfficiency),
    )
        isfinite(value) || push!(errs, "NaturalGas.$name must be finite")
        value >= 0 || push!(errs, "NaturalGas.$name must be non-negative")
    end
    gas.mwhPerTon > 0 || push!(errs, "NaturalGas.mwhPerTon must be positive")
    gas.storageInitialFraction <= 1 ||
        push!(errs, "NaturalGas.storageInitialFraction must be at most 1")
    gas.storageChargeEfficiency <= 1 ||
        push!(errs, "NaturalGas.storageChargeEfficiency must be at most 1")
    gas.storageDischargeEfficiency <= 1 ||
        push!(errs, "NaturalGas.storageDischargeEfficiency must be at most 1")
    gas.weatherScenarioCount > 0 ||
        push!(errs, "NaturalGas.weatherScenarioCount must be positive")
    gas.gasScenarioCount > 0 ||
        push!(errs, "NaturalGas.gasScenarioCount must be positive")

    # Missing functionality, deliberately gated rather than shipped half-verified:
    # the stochastic gas-price axis (gasScenarioCount > 1) is implemented on the
    # evidence branches, but the weather x gas scenario-combination convention has
    # never been verified against InternalEMPIRE's `empire.py`, and no
    # two-price-scenario reference parity exists. Until that evidence exists the
    # deterministic delivery refuses to build rather than risk silently mis-weighting
    # scenarios. Lifting the gate requires: (1) verifying the combination order
    # against the reference, (2) a stochastic parity comparison, (3) removing this
    # validation error.
    gas.gasScenarioCount == 1 || push!(
        errs,
        "NaturalGas.gasScenarioCount must equal 1: multiple gas-price scenarios " *
        "have not been verified against InternalEMPIRE",
    )

    for (name, values) in (
        ("pipelineCapacity", gas.pipelineCapacity),
        ("terminalCost", gas.terminalCost),
        ("terminalCapacity", gas.terminalCapacity),
        ("storageCapacity", gas.storageCapacity),
        ("reserves", gas.reserves),
        ("transportDemand", gas.transportDemand),
    )
        for (key, value) in values
            isfinite(value) ||
                push!(errs, "NaturalGas.$name[$key] must be finite")
            value >= 0 ||
                push!(errs, "NaturalGas.$name[$key] must be non-negative")
        end
    end

    sets === nothing && return
    gas_sets = natural_gas_sets(sets)
    isempty(gas_sets.Node) && return
    node_set = Set(gas_sets.Node)
    link_set = Set(gas_sets.DirectionalLink)
    terminal_pair_set = Set(gas_sets.TerminalsOfNode)
    for key in keys(gas.pipelineCapacity)
        key in link_set ||
            push!(errs, "NaturalGas.pipelineCapacity has unknown link key: $key")
    end
    for key in keys(gas.storageCapacity)
        key in node_set ||
            push!(errs, "NaturalGas.storageCapacity has unknown node key: $key")
    end
    for key in keys(gas.reserves)
        key in node_set ||
            push!(errs, "NaturalGas.reserves has unknown node key: $key")
    end
    for key in keys(gas.terminalCapacity)
        key[1:2] in terminal_pair_set ||
            push!(errs, "NaturalGas.terminalCapacity has unknown terminal key: $key")
    end
    for key in keys(gas.terminalCost)
        key[1:2] in terminal_pair_set ||
            push!(errs, "NaturalGas.terminalCost has unknown terminal key: $key")
        key[4] in 1:gas.gasScenarioCount ||
            push!(errs, "NaturalGas.terminalCost has invalid gas scenario key: $key")
    end
    for key in keys(gas.transportDemand)
        key[1] in gas_sets.OnshoreNode ||
            push!(errs, "NaturalGas.transportDemand has unknown onshore-node key: $key")
    end
    # The gas-to-power conversion divides by generator efficiency, so a missing
    # profile would otherwise surface as a bare KeyError during model building.
    for generator in gas_sets.Generator
        haskey(par.genEfficiency, generator) ||
            push!(
                errs,
                "NaturalGas generator $generator has no genEfficiency profile",
            )
    end

    periods === nothing && return
    period_count = length(strat_periods(periods))
    expected_pipeline = link_set
    expected_terminal_capacity = Set(
        (node, terminal, period)
        for (node, terminal) in gas_sets.TerminalsOfNode for period in 1:period_count
    )
    expected_terminal_cost = Set(
        (node, terminal, period, gas_scenario)
        for (node, terminal) in gas_sets.TerminalsOfNode for period in 1:period_count
        for gas_scenario in 1:gas.gasScenarioCount
    )
    expected_transport = Set(
        (node, period) for node in gas_sets.OnshoreNode for period in 1:period_count
    )
    expected_reserves = Set(
        node
        for (node, terminal) in gas_sets.TerminalsOfNode
        if is_finite_reserve_terminal(terminal)
    )
    for (name, expected, actual) in (
        ("pipelineCapacity", expected_pipeline, Set(keys(gas.pipelineCapacity))),
        ("terminalCapacity", expected_terminal_capacity, Set(keys(gas.terminalCapacity))),
        ("terminalCost", expected_terminal_cost, Set(keys(gas.terminalCost))),
        ("transportDemand", expected_transport, Set(keys(gas.transportDemand))),
        ("reserves", expected_reserves, Set(keys(gas.reserves))),
    )
        missing = setdiff(expected, actual)
        isempty(missing) ||
            push!(errs, "NaturalGas.$name is missing $(length(missing)) required key(s)")
    end
    return
end

"""
    validate_natural_gas(par, sets, periods)

Return the natural-gas validation issues for `par` as a vector of strings.

The general [`validate`](@ref) entry point is called with `strict = false` during
model building, which downgrades every issue to a single warning. Natural-gas
inputs cannot tolerate that: a missing terminal cost silently becomes 99999
EUR/t and a missing capacity silently becomes zero, so `create_model` treats
these issues as fatal whenever the module is enabled.
"""
function validate_natural_gas(
    par::EmpireParams,
    sets::EmpireSets,
    periods::Union{Nothing, TimeStructure} = nothing,
)
    errs = String[]
    _check_natural_gas_params!(errs, par, sets, periods)
    return errs
end

function _check_hydrogen_values!(errs, name, values; min = 0.0, max = nothing)
    for (key, value) in values
        isfinite(value) || push!(errs, "Hydrogen.$name[$key] must be finite")
        value >= min || push!(errs, "Hydrogen.$name[$key] must be at least $min")
        max !== nothing && value > max &&
            push!(errs, "Hydrogen.$name[$key] must be at most $max")
    end
    return
end

function _check_hydrogen_params!(
    errs::Vector{String},
    par::EmpireParams,
    sets::Union{Nothing, EmpireSets},
    periods::Union{Nothing, TimeStructure},
)
    hydrogen = par.Hydrogen
    module_present = sets !== nothing && has_hydrogen(sets)
    has_inputs = !isempty(hydrogen.electrolyzerCapitalCost)
    (module_present || has_inputs) || return

    for (name, value, positive, at_most_one) in (
        ("electrolyzerLifetime", hydrogen.electrolyzerLifetime, true, false),
        ("pipelineCompressorPowerUsage", hydrogen.pipelineCompressorPowerUsage, false, false),
        ("co2PipelineCapitalCost", hydrogen.co2PipelineCapitalCost, false, false),
        ("co2PipelineFixedOMCost", hydrogen.co2PipelineFixedOMCost, false, false),
        ("co2PipelineElectricityUsage", hydrogen.co2PipelineElectricityUsage, false, false),
        ("co2PipelineLifetime", hydrogen.co2PipelineLifetime, true, false),
        ("hydrogenMWhPerTon", hydrogen.hydrogenMWhPerTon, true, false),
        ("storageInitialFraction", hydrogen.storageInitialFraction, false, true),
        ("storageCompressionMWhPerTon", hydrogen.storageCompressionMWhPerTon, false, false),
        ("pipelineCompressorStaticMWhPerTon", hydrogen.pipelineCompressorStaticMWhPerTon, false, false),
        ("pipelineLifetime", hydrogen.pipelineLifetime, true, false),
        ("pipelineLeakageFractionPerKM", hydrogen.pipelineLeakageFractionPerKM, false, true),
        ("reformerRampFractionPerHour", hydrogen.reformerRampFractionPerHour, false, true),
        ("repurposeCostFactor", hydrogen.repurposeCostFactor, false, true),
        ("repurposeEnergyFlowFactor", hydrogen.repurposeEnergyFlowFactor, false, true),
        ("terminalEURPerKgToEURPerTon", hydrogen.terminalEURPerKgToEURPerTon, true, false),
        ("hoursPerYear", hydrogen.hoursPerYear, true, false),
    )
        isfinite(value) || push!(errs, "Hydrogen.$name must be finite")
        value >= 0 || push!(errs, "Hydrogen.$name must be non-negative")
        positive && value <= 0 && push!(errs, "Hydrogen.$name must be positive")
        at_most_one && value > 1 && push!(errs, "Hydrogen.$name must be at most 1")
    end

    for (name, values) in (
        ("electrolyzerCapitalCost", hydrogen.electrolyzerCapitalCost),
        ("electrolyzerFixedOMCost", hydrogen.electrolyzerFixedOMCost),
        ("electrolyzerPowerUse", hydrogen.electrolyzerPowerUse),
        ("reformerCapitalCost", hydrogen.reformerCapitalCost),
        ("reformerFixedOMCost", hydrogen.reformerFixedOMCost),
        ("reformerVariableOMCost", hydrogen.reformerVariableOMCost),
        ("reformerEmissionFactor", hydrogen.reformerEmissionFactor),
        ("reformerCO2CaptureFactor", hydrogen.reformerCO2CaptureFactor),
        ("reformerLifetime", hydrogen.reformerLifetime),
        ("pipelineCapitalCost", hydrogen.pipelineCapitalCost),
        ("pipelineOMCostPerKM", hydrogen.pipelineOMCostPerKM),
        ("storageCapitalCost", hydrogen.storageCapitalCost),
        ("storageFixedOMCost", hydrogen.storageFixedOMCost),
        ("storageLifetime", hydrogen.storageLifetime),
        ("storageMaxCapacity", hydrogen.storageMaxCapacity),
        ("terminalInitialCapacity", hydrogen.terminalInitialCapacity),
        ("terminalCapitalCost", hydrogen.terminalCapitalCost),
        ("terminalFixedOMCost", hydrogen.terminalFixedOMCost),
        ("terminalPrice", hydrogen.terminalPrice),
        ("terminalLifetime", hydrogen.terminalLifetime),
        ("electricityTransportDemand", hydrogen.electricityTransportDemand),
        ("hydrogenTransportDemand", hydrogen.hydrogenTransportDemand),
        ("generatorCO2Captured", hydrogen.generatorCO2Captured),
        ("co2StorageMaxCapacity", hydrogen.co2StorageMaxCapacity),
        ("co2MaxSequestrationCapacity", hydrogen.co2MaxSequestrationCapacity),
        ("co2StorageSiteCapitalCost", hydrogen.co2StorageSiteCapitalCost),
        ("co2StorageSiteFixedOMCost", hydrogen.co2StorageSiteFixedOMCost),
    )
        _check_hydrogen_values!(errs, name, values)
    end
    _check_hydrogen_values!(errs, "reformerEfficiency", hydrogen.reformerEfficiency; max = 1.0)
    for (key, value) in hydrogen.reformerEfficiency
        value > 0 || push!(errs, "Hydrogen.reformerEfficiency[$key] must be positive")
    end
    for (key, value) in hydrogen.reformerElectricityUse
        isfinite(value) || push!(errs, "Hydrogen.reformerElectricityUse[$key] must be finite")
        value < 0 && key[1] != "SMR" && push!(
            errs,
            "Hydrogen.reformerElectricityUse[$key] may be negative only for the audited SMR source row",
        )
    end
    for (name, values) in (
        ("reformerLifetime", hydrogen.reformerLifetime),
        ("storageLifetime", hydrogen.storageLifetime),
        ("terminalLifetime", hydrogen.terminalLifetime),
    )
        for (key, value) in values
            value > 0 || push!(errs, "Hydrogen.$name[$key] must be positive")
        end
    end

    sets === nothing && return
    hsets = hydrogen_sets(sets)
    production_nodes = Set(hsets.ProductionNode)
    reformer_plants = Set(hsets.ReformerPlant)
    storage_set = Set(hsets.Storage)
    terminal_pairs = Set(hsets.TerminalsOfNode)
    terminal_set = Set(hsets.Terminal)
    co2_nodes = Set(hsets.CO2SequestrationNode)
    generator_set = Set(generators(sets))
    for (key, _) in hydrogen.storageMaxCapacity
        key[1] in production_nodes || push!(errs, "Hydrogen.storageMaxCapacity has unknown node: $key")
        key[2] in storage_set || push!(errs, "Hydrogen.storageMaxCapacity has unknown storage: $key")
    end
    for (name, values) in (
        ("terminalInitialCapacity", hydrogen.terminalInitialCapacity),
        ("terminalCapitalCost", hydrogen.terminalCapitalCost),
        ("terminalFixedOMCost", hydrogen.terminalFixedOMCost),
        ("terminalPrice", hydrogen.terminalPrice),
    )
        for key in keys(values)
            key[1:2] in terminal_pairs || push!(errs, "Hydrogen.$name has unknown terminal pair: $key")
        end
    end
    for key in keys(hydrogen.terminalLifetime)
        key in terminal_set || push!(errs, "Hydrogen.terminalLifetime has unknown terminal: $key")
    end
    for (name, values) in (
        ("reformerCapitalCost", hydrogen.reformerCapitalCost),
        ("reformerFixedOMCost", hydrogen.reformerFixedOMCost),
        ("reformerVariableOMCost", hydrogen.reformerVariableOMCost),
        ("reformerEfficiency", hydrogen.reformerEfficiency),
        ("reformerElectricityUse", hydrogen.reformerElectricityUse),
        ("reformerEmissionFactor", hydrogen.reformerEmissionFactor),
        ("reformerCO2CaptureFactor", hydrogen.reformerCO2CaptureFactor),
    )
        for key in keys(values)
            key[1] in reformer_plants || push!(errs, "Hydrogen.$name has unknown reformer: $key")
        end
    end
    for key in keys(hydrogen.generatorCO2Captured)
        key in generator_set || push!(errs, "Hydrogen.generatorCO2Captured has unknown generator: $key")
    end
    for (name, values) in (
        ("co2StorageMaxCapacity", hydrogen.co2StorageMaxCapacity),
        ("co2MaxSequestrationCapacity", hydrogen.co2MaxSequestrationCapacity),
        ("co2StorageSiteCapitalCost", hydrogen.co2StorageSiteCapitalCost),
        ("co2StorageSiteFixedOMCost", hydrogen.co2StorageSiteFixedOMCost),
    )
        for key in keys(values)
            node = key isa Tuple ? key[1] : key
            node in co2_nodes || push!(errs, "Hydrogen.$name has unknown CO2 node: $key")
        end
    end

    periods === nothing && return
    period_ids = Set(1:length(strat_periods(periods)))
    expected_plant_periods = Set((plant, period) for plant in reformer_plants for period in period_ids)
    expected_terminal_periods = Set(
        (node, terminal, period) for (node, terminal) in terminal_pairs for period in period_ids
    )
    expected_transport = Set(
        (node, period) for node in natural_gas_onshore_nodes(sets) for period in period_ids
    )
    expected_co2_periods = Set((node, period) for node in co2_nodes for period in period_ids)
    for (name, expected, actual) in (
        ("electrolyzerCapitalCost", period_ids, Set(keys(hydrogen.electrolyzerCapitalCost))),
        ("electrolyzerFixedOMCost", period_ids, Set(keys(hydrogen.electrolyzerFixedOMCost))),
        ("electrolyzerPowerUse", period_ids, Set(keys(hydrogen.electrolyzerPowerUse))),
        ("pipelineCapitalCost", period_ids, Set(keys(hydrogen.pipelineCapitalCost))),
        ("pipelineOMCostPerKM", period_ids, Set(keys(hydrogen.pipelineOMCostPerKM))),
        ("reformerCapitalCost", expected_plant_periods, Set(keys(hydrogen.reformerCapitalCost))),
        ("reformerFixedOMCost", expected_plant_periods, Set(keys(hydrogen.reformerFixedOMCost))),
        ("reformerVariableOMCost", expected_plant_periods, Set(keys(hydrogen.reformerVariableOMCost))),
        ("reformerEfficiency", expected_plant_periods, Set(keys(hydrogen.reformerEfficiency))),
        ("reformerElectricityUse", expected_plant_periods, Set(keys(hydrogen.reformerElectricityUse))),
        ("reformerEmissionFactor", expected_plant_periods, Set(keys(hydrogen.reformerEmissionFactor))),
        ("reformerCO2CaptureFactor", expected_plant_periods, Set(keys(hydrogen.reformerCO2CaptureFactor))),
        ("terminalInitialCapacity", expected_terminal_periods, Set(keys(hydrogen.terminalInitialCapacity))),
        ("terminalCapitalCost", expected_terminal_periods, Set(keys(hydrogen.terminalCapitalCost))),
        ("terminalFixedOMCost", expected_terminal_periods, Set(keys(hydrogen.terminalFixedOMCost))),
        ("terminalPrice", expected_terminal_periods, Set(keys(hydrogen.terminalPrice))),
        ("electricityTransportDemand", expected_transport, Set(keys(hydrogen.electricityTransportDemand))),
        ("hydrogenTransportDemand", expected_transport, Set(keys(hydrogen.hydrogenTransportDemand))),
        ("co2StorageMaxCapacity", expected_co2_periods, Set(keys(hydrogen.co2StorageMaxCapacity))),
    )
        missing = setdiff(expected, actual)
        isempty(missing) || push!(errs, "Hydrogen.$name is missing $(length(missing)) required key(s)")
        # A self-contained dataset may cover more strategic periods than a reduced
        # smoke/parity configuration uses. Those later rows are valid source data;
        # only absence of an active-period key is a model error.
    end
    Set(keys(hydrogen.reformerLifetime)) == reformer_plants ||
        push!(errs, "Hydrogen.reformerLifetime does not exactly cover ReformerPlant")
    Set(keys(hydrogen.storageLifetime)) == storage_set ||
        push!(errs, "Hydrogen.storageLifetime does not exactly cover Storage")
    Set(keys(hydrogen.terminalLifetime)) == terminal_set ||
        push!(errs, "Hydrogen.terminalLifetime does not exactly cover Terminal")
    return
end

"""Return fatal deterministic Hydrogen/CO₂ input issues."""
function validate_hydrogen(
    par::EmpireParams,
    sets::EmpireSets,
    periods::Union{Nothing, TimeStructure} = nothing,
)
    errs = String[]
    _check_hydrogen_params!(errs, par, sets, periods)
    return errs
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
   - `storageDiscToCharRatio` is non-negative.
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
function validate(
        par::EmpireParams; sets::Union{Nothing, EmpireSets} = nothing,
        periods::Union{Nothing, TimeStructure} = nothing,
        strict::Bool = true
    )
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
    _check_float_dict!(errs, "storageDiscToCharRatio", par.storageDiscToCharRatio; min = 0.0)
    _check_float_dict!(errs, "storagePowToEnergy", par.storagePowToEnergy; min = 0.0)
    _check_float_dict!(errs, "storENMaxInstalledCap", par.storENMaxInstalledCap; min = 0.0)
    _check_float_dict!(errs, "storPWMaxInstalledCap", par.storPWMaxInstalledCap; min = 0.0)
    _check_float_dict!(errs, "storOperationalInit", par.storOperationalInit; min = 0.0, max = 1.0)
    _check_float_dict!(errs, "storageLifetime", par.storageLifetime; min = nextfloat(0.0))

    _check_float_dict!(errs, "maxHydroNode", par.maxHydroNode; min = 0.0)

    # TimeProfile dicts
    for (name, d) in (
            ("genCapitalCost", par.genCapitalCost),
            ("genFixedOMCost", par.genFixedOMCost),
            ("genFuelCost", par.genFuelCost),
            ("genScaleInitCap", par.genScaleInitCap),
            ("genInitCap", par.genInitCap),
            ("genMaxBuiltCap", par.genMaxBuiltCap),
            ("genMaxInstalledCap", par.genMaxInstalledCap),
            ("transmissionInitCap", par.transmissionInitCap),
            ("transmissionMaxBuiltCap", par.transmissionMaxBuiltCap),
            ("transmissionMaxInstalledCap", par.transmissionMaxInstalledCap),
            ("transmissionTypeCapitalCost", par.transmissionTypeCapitalCost),
            ("transmissionTypeFixedOMCost", par.transmissionTypeFixedOMCost),
            ("storENCapitalCost", par.storENCapitalCost),
            ("storENFixedOMCost", par.storENFixedOMCost),
            ("storENInitCap", par.storENInitCap),
            ("storENMaxBuiltCap", par.storENMaxBuiltCap),
            ("storPWCapitalCost", par.storPWCapitalCost),
            ("storPWFixedOMCost", par.storPWFixedOMCost),
            ("storPWInitCap", par.storPWInitCap),
            ("storPWMaxBuiltCap", par.storPWMaxBuiltCap),
            ("nodeLostLoadCost", par.nodeLostLoadCost),
            ("sloadAnnualDemand", par.sloadAnnualDemand),
            ("sloadRaw", par.sloadRaw),
            ("sload", par.sload),
            ("maxRegHydroGenRaw", par.maxRegHydroGenRaw),
            ("maxRegHydroGen", par.maxRegHydroGen),
            ("genInvCost", par.genInvCost),
            ("storENInvCost", par.storENInvCost),
            ("storPWInvCost", par.storPWInvCost),
            ("transmissionInvCost", par.transmissionInvCost),
            ("genMargCost", par.genMargCost),
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
    _check_natural_gas_params!(errs, par, sets, periods)
    _check_hydrogen_params!(errs, par, sets, periods)

    # Index checks (only if a set is provided)
    if sets !== nothing
        gset = Set(generators(sets))
        sset = Set(storages(sets))
        nset = Set(nodes(sets))
        ttset = Set(transmission_types(sets))
        arcset = Set(arcs(sets))
        ng_pairs = Set(node_generators(sets))
        ns_pairs = Set(node_storages(sets))

        # String-keyed dicts indexed by generator
        for (name, d) in (
                ("genCapitalCost", par.genCapitalCost),
                ("genFixedOMCost", par.genFixedOMCost),
                ("genVariableOMCost", par.genVariableOMCost),
                ("genFuelCost", par.genFuelCost),
                ("genEfficiency", par.genEfficiency),
                ("genScaleInitCap", par.genScaleInitCap),
                ("genRampUpCap", par.genRampUpCap),
                ("genCapAvailType", par.genCapAvailType),
                ("genCO2Content", par.genCO2Content),
                ("genLifetime", par.genLifetime),
                ("genInvCost", par.genInvCost),
                ("genMargCost", par.genMargCost),
            )
            _check_keys_in_set!(errs, name, d, gset, "generator")
        end

        # String-keyed dicts indexed by storage
        for (name, d) in (
                ("storageBleedEff", par.storageBleedEff),
                ("storageChargeEff", par.storageChargeEff),
                ("storageDischargeEff", par.storageDischargeEff),
                ("storageDiscToCharRatio", par.storageDiscToCharRatio),
                ("storagePowToEnergy", par.storagePowToEnergy),
                ("storENCapitalCost", par.storENCapitalCost),
                ("storENFixedOMCost", par.storENFixedOMCost),
                ("storOperationalInit", par.storOperationalInit),
                ("storPWCapitalCost", par.storPWCapitalCost),
                ("storPWFixedOMCost", par.storPWFixedOMCost),
                ("storageLifetime", par.storageLifetime),
                ("storENInvCost", par.storENInvCost),
                ("storPWInvCost", par.storPWInvCost),
            )
            _check_keys_in_set!(errs, name, d, sset, "storage")
        end

        # String-keyed dicts indexed by node
        for (name, d) in (
                ("nodeLostLoadCost", par.nodeLostLoadCost),
                ("sloadAnnualDemand", par.sloadAnnualDemand),
                ("maxHydroNode", par.maxHydroNode),
                ("sloadRaw", par.sloadRaw),
                ("sload", par.sload),
                ("maxRegHydroGenRaw", par.maxRegHydroGenRaw),
                ("maxRegHydroGen", par.maxRegHydroGen),
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
                ("genRefInitCap", par.genRefInitCap),
                ("genInitCap", par.genInitCap),
                ("genCapAvail", par.genCapAvail),
            )
            _check_tuple_keys_in_sets!(
                errs, name, d, nset, "node", gset, "generator";
                allowed_pairs = ng_pairs
            )
        end

        # Tuple{node, technology} keyed dicts
        for (name, d) in (
                ("genMaxBuiltCap", par.genMaxBuiltCap),
                ("genMaxInstalledCapRaw", par.genMaxInstalledCapRaw),
                ("genMaxInstalledCap", par.genMaxInstalledCap),
            )
            _check_tuple_keys_in_sets!(errs, name, d, nset, "node", Set(techs(sets)), "technology")
        end

        # Tuple{node, storage} keyed dicts
        for (name, d) in (
                ("storENInitCap", par.storENInitCap),
                ("storENMaxBuiltCap", par.storENMaxBuiltCap),
                ("storENMaxInstalledCap", par.storENMaxInstalledCap),
                ("storPWInitCap", par.storPWInitCap),
                ("storPWMaxBuiltCap", par.storPWMaxBuiltCap),
                ("storPWMaxInstalledCap", par.storPWMaxInstalledCap),
            )
            _check_tuple_keys_in_sets!(
                errs, name, d, nset, "node", sset, "storage";
                allowed_pairs = ns_pairs
            )
        end

        # Tuple{node, node} keyed dicts (arcs)
        for (name, d) in (
                ("transmissionInitCap", par.transmissionInitCap),
                ("transmissionMaxBuiltCap", par.transmissionMaxBuiltCap),
                ("transmissionMaxInstalledCap", par.transmissionMaxInstalledCap),
                ("transmissionLength", par.transmissionLength),
                ("lineEfficiency", par.lineEfficiency),
                ("transmissionLifetime", par.transmissionLifetime),
                ("transmissionInvCost", par.transmissionInvCost),
            )
            _check_tuple_keys_in_sets!(
                errs, name, d, nset, "node", nset, "node";
                allowed_pairs = arcset
            )
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
