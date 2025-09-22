# Structs used to store parameters and sets for an EMPIRE model

mutable struct EmpireSets
    Generator
    ThermalGenerators
    HydroGenerator
    RegHydroGenerator
    Storage
    DependentStorage
    Technology
    Period
    Operationalhour
    Season
    Node
    DirectionalLink
    DirectionalLink_H2
    transmissionType
    transmissionType_H2
    Scenario
    transmissionTypeOfDirectionalLink
    transmissionTypeOfDirectionalLink_H2
    GeneratorsOfTechnology
    GeneratorsOfNode
    StoragesOfNode
    HoursOfSeason
    FirstHoursOfRegSeason
    FirstHoursOfPeakSeason
    ElToHeat
    ElToHeatOfNode
    GeneratorEL
    GeneratorTR
    StorageEL
    StorageTR
    StorageHydrogen
    StoragesOfHydrogen
    AvailableSale
    DependentStorageHydrogen
    BidirectionalArc
    BidirectionalArc_H2
    NodeGenTime
    NodeNodeTransm
    NodeNodeTransm_H2
    NodeStorTime

    EmpireSets() = new()
end

nodes(sets::EmpireSets) = sets.Node
generators(sets::EmpireSets) = sets.Generator
storages(sets::EmpireSets) = sets.Storage
techs(sets::EmpireSets) = sets.Technology
transmission_types(sets::EmpireSets) = sets.transmissionType

generators(sets::EmpireSets, n) = [g for (nn, g) in sets.GeneratorsOfNode if nn == n]
storages(sets::EmpireSets, n) = [s for (nn, s) in sets.StoragesOfNode if nn == n]
techs(sets::EmpireSets, n) = [t for (t, g) in sets.GeneratorsOfTechnology if (n, g) in sets.GeneratorsOfNode]
generators_tech(sets::EmpireSets, n, t) =
    [g for (tt, g) in sets.GeneratorsOfTechnology if tt == t && (n, g) in sets.GeneratorsOfNode]


mutable struct EmpireParams
    discountrate
    WACC
    LeapYearsInvestment
    operationalDiscountrate
    sceProbab
    seasScale
    lengthRegSeason
    lengthPeakSeason
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
    genCO2TypeFactor
    genRampUpCap
    genCapAvailTypeRaw
    transmissionInitCap
    transmissionMaxBuiltCap
    transmissionMaxInstalledCapRaw
    transmissionLength
    transmissionTypeCapitalCost
    transmissionTypeFixedOMCost
    transmissionInitCap_H2
    transmissionMaxBuiltCap_H2
    transmissionMaxInstalledCapRaw_H2
    transmissionLength_H2
    transmissionCapitalCost_H2
    transmissionFixedOMCost_H2
    lineEfficiency
    storageBleedEff
    storageChargeEff
    storageDischargeEff
    storagePowToEnergy
    storENCapitalCost
    storENFixedOMCost
    storENInitCap
    storENMaxBuiltCap
    storENMaxInstalledCapRaw
    storOperationalInit
    storPWCapitalCost
    storPWFixedOMCost
    storPWInitCap
    storPWMaxBuiltCap
    storPWMaxInstalledCapRaw
    nodeLostLoadCost
    sloadAnnualDemand
    CO2price
    maxHydroNode
    maxRegHydroGenRaw
    genCapAvailStochRaw
    sloadRaw
    genLifetime
    transmissionLifetime
    transmissionLifetime_H2
    storageLifetime
    CO2cap
    ElToHeatCapitalCost
    ElToHeatFixedOMCost
    μElToHeatInvCost
    ElToHeatLifetime
    ElToHeatEff
    ElToHeatInitCap
    ElToHeatMaxBuiltCap
    ElToHeatMaxInstalledCapRaw
    ElToHeatMaxInstalledCap
    sloadRawTR
    sloadAnnualDemandTR
    sloadTR
    EVdemand
    genRefInitCapNewnode
    genInitCapNewnode
    genMaxBuiltCapNewnode
    genMaxInstalledCapRawNewnode
    genCapitalCostNewnode
    genFixedOMCostNewnode
    lineEfficiencyNewnode
    transmissionInitCapNewnode
    transmissionMaxBuiltCapNewnode
    transmissionMaxInstalledCapRawNewnode
    storENInitCapNewnode
    storENMaxBuiltCapNewnode
    storENMaxInstalledCapRawNewnode
    storPWInitCapNewnode
    storPWMaxBuiltCapNewnode
    storPWMaxInstalledCapRawNewnode
    nodeLostLoadCostNewnode
    sloadAnnualDemandNewnode
    maxHydroNodeNewnode
    maxRegHydroGenRawNewnode
    genCapAvailStochRawNewnode
    sloadRawNewnode
    transmissionLifetimeNewnode
    genLifetimeNewnode
    HydrogenPrice
    MaxHydrogenDemand
    genInvCost
    storENInvCost
    storPWInvCost
    transmissionInvCost
    transmissionInvCost_H2
    genMargCost
    μgenInitCap
    transmissionMaxInstalledCap
    transmissionMaxInstalledCap_H2
    operationalDiscountRate
    genMaxInstalledCap
    storENMaxInstalledCap
    storPWMaxInstalledCap
    maxRegHydroGen
    genCapAvail
    sload

    EmpireParams() = new()
end

# Helper functions to get parameter values with default fallbacks

# Generator properties
gencap_avail(par, n, g, t) = get(par.genCapAvail, (n, g, t), 0.0)
rampup_cap(par, g) = get(par.genRampUpCap, g, 0.0)
max_build_cap(par, n, t, sp) = get(par.genMaxBuiltCap, (n, t, sp), nothing)
max_inst_cap(par, n, t, sp) = get(par.genMaxInstalledCap, (n, t, sp), nothing)
gen_lifetime(par, g) = get(par.genLifetime, g, 1)
gencap_init(par, n, g, sp) = get(par.genInitCap, (n, g, sp), 0.0)

# Storage properties
bleed_eff(par, s) = get(par.storageBleedEff, s, 1.0)
charge_eff(par, s) = get(par.storageChargeEff, s, 1.0)
discharge_eff(par, s) = get(par.storageDischargeEff, s, 1.0)
storage_init(par, s) = get(par.storOperationalInit, s, 0.0)
lifetime_storage(par, s) = get(par.storageLifetime, s, 1)
stor_cap_init_en(par, s, sp) = get(par.storENInitCap, (s, sp), 0.0)
stor_cap_init_pow(par, s, sp) = get(par.storPWInitCap, (s, sp), 0.0)

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
