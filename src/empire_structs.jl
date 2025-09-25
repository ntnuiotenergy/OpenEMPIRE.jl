# Structs used to store parameters and sets for an EMPIRE model

mutable struct EmpireSets
    Generator
    ThermalGenerators
    HydroGenerator
    RegHydroGenerator
    Storage
    DependentStorage
    Technology
    Node
    DirectionalLink
    TransmissionType
    TransmissionTypeOfDirectionalLink
    GeneratorsOfTechnology
    GeneratorsOfNode
    StoragesOfNode

    EmpireSets() = new()
end

nodes(sets::EmpireSets) = sets.Node
generators(sets::EmpireSets) = sets.Generator
storages(sets::EmpireSets) = sets.Storage
dependent_storages(sets::EmpireSets) = sets.DependentStorage
techs(sets::EmpireSets) = sets.Technology
transmission_types(sets::EmpireSets) = sets.TransmissionType
arcs(sets::EmpireSets) = sets.DirectionalLink

generators(sets::EmpireSets, n) = [g for (nn, g) in sets.GeneratorsOfNode if nn == n]
storages(sets::EmpireSets, n) = [s for (nn, s) in sets.StoragesOfNode if nn == n]
techs(sets::EmpireSets, n) = unique([t for (t, g) in sets.GeneratorsOfTechnology if (n, g) in sets.GeneratorsOfNode])
generators_tech(sets::EmpireSets, n, t) =
    unique([g for (tt, g) in sets.GeneratorsOfTechnology if tt == t && (n, g) in sets.GeneratorsOfNode])


mutable struct EmpireParams
    # Financial parameters
    WACC
    discountRate
    # Generator inputs from file
    genCapitalCost
    genFixedOMCost
    genVariableOMCost
    genFuelCost
    CCSCostTSVariable
    genEfficiency
    genRefInitCap
    genScaleInitCap
    genInitCap
    genMaxBuiltCap
    genMaxInstalledCapRaw
    genMaxInstalledCap
    genRampUpCap
    genCapAvailType
    genCO2Content
    genLifetime
    # Transmission inputs from file
    transmissionInitCap
    transmissionMaxBuiltCap
    transmissionMaxInstalledCap
    transmissionLength
    transmissionTypeCapitalCost
    transmissionTypeFixedOMCost
    lineEfficiency
    transmissionLifetime
    # Storage inputs from file
    storageBleedEff
    storageChargeEff
    storageDischargeEff
    storagePowToEnergy
    storENCapitalCost
    storENFixedOMCost
    storENInitCap
    storENMaxBuiltCap
    storENMaxInstalledCap
    storOperationalInit
    storPWCapitalCost
    storPWFixedOMCost
    storPWInitCap
    storPWMaxBuiltCap
    storPWMaxInstalledCap
    storageLifetime
    # Node inputs from file
    nodeLostLoadCost
    sloadAnnualDemand
    maxRegHydroGenRaw
    # General parameters from file
    CO2cap
    CO2price

    # Stochastic parameters
    sloadRaw::Dict{String, TimeProfile}
    sload::Dict{String, TimeProfile}
    genCapAvail::Dict{Tuple{String,String}, TimeProfile}
    maxRegHydroGen::Dict{String, Float64}

    # Processed parameters
    genInvCost::Dict{String, TimeProfile}
    storENInvCost::Dict{String, TimeProfile}
    storPWInvCost::Dict{String, TimeProfile}
    transmissionInvCost::Dict{Tuple{String,String}, TimeProfile}
    genMargCost::Dict{String, TimeProfile}

    maxHydroNode

    EmpireParams() = new()
end

# Helper functions to get parameter values with default fallbacks, the model should
# only use these functions to access parameter values

# General properties
load(par, n, t) = haskey(par.sload, n) ? par.sload[n][t] : 0.0

# Generator properties
gencap_avail(par, n, g, t) =
    haskey(par.genCapAvail, (n, g)) ? par.genCapAvail[(n, g)][t] : par.genCapAvailType[g]
rampup_cap(par, g) = get(par.genRampUpCap, g, 1.0)
max_build_cap(par, n, gt, sp) = (n, gt) in keys(par.genMaxBuiltCap) ? par.genMaxBuiltCap[(n, gt)][sp] : nothing
max_inst_cap(par, n, gt, sp) = (n, gt) in keys(par.genMaxInstalledCap) ? par.genMaxInstalledCap[(n, gt)][sp] : nothing
gen_lifetime(par, g) = get(par.genLifetime, g, 40)
gencap_init(par, n, g, sp) = (n, g) in keys(par.genInitCap) ? par.genInitCap[(n, g)][sp] : 0.0

# Storage properties
bleed_eff(par, s) = get(par.storageBleedEff, s, 1.0)
charge_eff(par, s) = get(par.storageChargeEff, s, 1.0)
discharge_eff(par, s) = get(par.storageDischargeEff, s, 1.0)
storage_init(par, s) = get(par.storOperationalInit, s, 0.0)
lifetime_storage(par, s) = get(par.storageLifetime, s, 1)
stor_cap_init_en(par, s, sp) = haskey(par.storENInitCap, s) ? par.storENInitCap[s][sp] : 0.0
stor_cap_init_pow(par, s, sp) = haskey(par.storPWInitCap, s) ? par.storPWInitCap[s][sp] : 0.0
power_to_energy(par, s) = get(par.storagePowToEnergy, s, 1.0)

# Transmission properties
trans_cap_init(par, m, n, sp) = haskey(par.transmissionInitCap, (m, n)) ? par.transmissionInitCap[(m, n)][sp] : 0.0
trans_lifetime(par, m, n) = get(par.transmissionLifetime, (m, n), 40)
trans_max_build_cap(par, m, n, sp) = haskey(par.transmissionMaxBuiltCap, (m, n)) ? par.transmissionMaxBuiltCap[(m, n)][sp] : nothing
line_eff(par, m, n) = get(par.lineEfficiency, (m, n), 1.0)

# Cost properties
gen_invest_cost(par, g, sp) = haskey(par.genInvCost, g) ? par.genInvCost[g][sp] : 0.0
stor_en_invest_cost(par, s, sp) = haskey(par.storENInvCost, s) ? par.storENInvCost[s][sp] : 0.0
stor_pw_invest_cost(par, s, sp) = haskey(par.storPWInvCost, s) ? par.storPWInvCost[s][sp] : 0.0
trans_invest_cost(par, m, n, sp) = haskey(par.transmissionInvCost, (m, n)) ? par.transmissionInvCost[(m, n)][sp] : 0.0

lost_load_cost(par, n, t) = haskey(par.nodeLostLoadCost, n) ? par.nodeLostLoadCost[n][t] : 1000.0
sload(par, n, t) = haskey(par.sload, n) ? par.sload[n][t] : 0.0
max_reg_hydro_gen(par, n) = get(par.maxRegHydroGen, n, 0.0)
gen_marginal_cost(par, g, t) = haskey(par.genMargCost, g) ? par.genMargCost[g][t] : 0.0

mutable struct empire_opt
    EMISSION_CAP
    NAME
    WRITE_LP
    HEATMODULE
    EVMODULE
    SoldInFlow
    NEWNODE
    USUAL
    AMBITIOUS
    MODERATE
    HYDROGEN
    H2MIN
    H2MAX
    HYDROGEN_TRANSPORT

    empire_opt() = new()
end

mutable struct empire_mod
    genInvCap
    transmissionInvCap
    transmissionInvCap_H2
    storPWInvCap
    storENInvCap
    genOperational
    storOperational
    transmissionOperational
    transmissionOperational_H2
    storCharge
    storDischarge
    loadShed
    genInstalledCap
    transmissionInstalledCap
    transmissionInstalledCap_H2
    storPWInstalledCap
    storENInstalledCap
    amountsold
    obj
    ElToHeatOperational
    ElToHeatInvCap
    ElToHeatInstalledCap
    loadShedTR
    storMovedIn
    storMovedOut

    empire_mod() = new()
end
