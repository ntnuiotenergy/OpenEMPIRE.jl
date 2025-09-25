
function read_sets_xlsx(dirX)
    # Read the data from the xlsx files
    @info "Reading sets from $dirX"

    sets = OpenEMPIRE.EmpireSets()

    XLSX.openxlsx(joinpath(dirX, "Sets.xlsx")) do filehandle
        sets.Generator = filehandle["Generators"][:][2:end, 1]
        sets.ThermalGenerators = filehandle["Generators"][:][2:end, 4]
        sets.HydroGenerator = filehandle["Generators"][:][2:end, 3]
        sets.RegHydroGenerator = filehandle["Generators"][:][2:end, 2]
        sets.Storage = filehandle["Storage"][:][2:end, 1]
        sets.DependentStorage = filehandle["Storage"][:][4:end, 2]
        sets.Technology = filehandle["Technology"][:][2:end, 1]
        sets.Node = filehandle["Nodes"][:][2:end, 1]
        sets.DirectionalLink = filehandle["DirectionalLines"][:][4:end, 1:2] |> d -> Tuple.(eachrow(d))
        sets.TransmissionType = filehandle["LineType"][:][2:end, 1]
        sets.TransmissionTypeOfDirectionalLink = filehandle["LineTypeOfDirectionalLines"][:][4:end, 1:3] |> d -> Tuple.(eachrow(d))
        sets.GeneratorsOfTechnology = filehandle["GeneratorsOfTechnology"][:][4:end, 1:2] |> d -> Tuple.(eachrow(d))
        sets.GeneratorsOfNode = filehandle["GeneratorsOfNode"][:][4:end, 1:2] |> d -> Tuple.(eachrow(d))
        sets.StoragesOfNode = filehandle["StorageOfNodes"][:][4:end, 1:2] |> d -> Tuple.(eachrow(d))
    end

    # Clear missing values from sets
    sets.ThermalGenerators = filter(!ismissing, sets.ThermalGenerators)
    sets.HydroGenerator = filter(!ismissing, sets.HydroGenerator)
    sets.RegHydroGenerator = filter(!ismissing, sets.RegHydroGenerator)
    sets.DependentStorage = filter(!ismissing, sets.DependentStorage)

    return sets
end

# Remove rows where there are missing values in the first column
function purge_missing(data)
    # Find the first row with missing values in the first column
    first_missing_row = findfirst(row -> ismissing(row[1]), eachrow(data))
    if first_missing_row !== nothing
        data = data[1:first_missing_row-1, :]
    end
    return data
end

function param_load(temp; value_col=2)
    temp = purge_missing(temp)
    values = Dict()
    for row in eachrow(temp)
        values[row[1:value_col-1]...] = row[value_col]
    end
    return values
end

function strat_profiles(data; default_value=0.0)
    # Create strategic profiles from the data assuming the first column is the name,
    # the next column is the strategic period, and the last column is the value

    data = purge_missing(data)

    # Extract unique names and strat periods
    names = unique(data[:, 1])
    strat_periods = 1 : maximum(data[:, 2])

    # Create a dictionary to hold the strategic profiles
    profiles = Dict{String, StrategicProfile}()

    for name in names
        values = FixedProfile[]
        for period in strat_periods
            value = get(data[(data[:, 1] .== name) .& (data[:, 2] .== period), 3], 1, default_value)
            push!(values, FixedProfile(value))
        end
        profiles[name] = StrategicProfile(values)
    end

    return profiles
end

function strat_profiles_gen(data; default_value=0.0)
    # Create strategic profiles from the data assuming the first column is the node,
    # the second is the generator/technology,
    # the next column is the strategic period, and the last column is the value

    data = purge_missing(data)

    # Extract unique (names, gen/tech) and strat periods
    node_gen = unique(Tuple.(eachrow(data[:, 1:2])))
    strat_periods = 1 : maximum(data[:, 3])

    # Create a dictionary to hold the strategic profiles
    profiles = Dict{Tuple{String,String}, StrategicProfile}()

    for ng in node_gen
        values = FixedProfile[]
        for period in strat_periods
            value = get(data[(data[:, 1] .== ng[1]) .& (data[:, 2] .== ng[2]) .& (data[:, 3] .== period), 4], 1, default_value)
            push!(values, FixedProfile(value))
        end
        profiles[ng] = StrategicProfile(values)
    end

    return profiles
end

function strat_profile(data; default_value=0.0)
    # Create a strategic profile from the data assuming the first column is the strategic period
    # and the last column is the value
    data = purge_missing(data)
    strat_periods = 1 : maximum(data[:, 1])
    values = FixedProfile[]
    for period in strat_periods
        value = get(data[data[:, 1] .== period, 2], 1, default_value)
        push!(values, FixedProfile(value))
    end
    return StrategicProfile(values)
end


function read_params_xlsx(dirX)
    # Read the data from the xlsx files
    @info "Reading parameters from $dirX"

    par = OpenEMPIRE.EmpireParams()

    # Generator parameters
    XLSX.openxlsx(joinpath(dirX, "Generator.xlsx")) do filehandle
        par.genCapitalCost = filehandle["CapitalCosts"][:][4:end,:]  |> data -> strat_profiles(data)
        par.genFixedOMCost = filehandle["FixedOMCosts"][:][4:end,:] |> data -> strat_profiles(data)
        par.genVariableOMCost = filehandle["VariableOMCosts"][:][4:end,:] |> data -> param_load(data)
        par.genFuelCost = filehandle["FuelCosts"][:][4:end,:] |> data -> strat_profiles(data)
        par.CCSCostTSVariable = filehandle["CCSCostTSVariable"][:][4:end,:] |> data -> strat_profile(data)
        par.genEfficiency = filehandle["Efficiency"][:][4:end,:] |> data -> strat_profiles(data)
        par.genRefInitCap = filehandle["RefInitialCap"][:][4:end,:] |> data -> param_load(data; value_col = 3)
        par.genScaleInitCap = filehandle["ScaleFactorInitialCap"][:][4:end,:] |> data -> strat_profiles(data)
        par.genInitCap = filehandle["InitialCapacity"][:][4:end,:] |> data -> strat_profiles_gen(data)
        par.genMaxBuiltCap = filehandle["MaxBuiltCapacity"][:][4:end,:] |> data -> strat_profiles_gen(data)
        par.genMaxInstalledCapRaw = filehandle["MaxInstalledCapacity"][:][4:end,:] |> data -> param_load(data; value_col = 3)
        par.genRampUpCap = filehandle["RampRate"][:][4:end,:] |> data -> param_load(data)
        par.genCapAvailType = filehandle["GeneratorTypeAvailability"][:][4:end,:] |> data -> param_load(data)
        par.genCO2Content = filehandle["CO2Content"][:][4:end,:] |> data -> param_load(data)
        par.genLifetime = filehandle["Lifetime"][:][4:end,:] |> data -> param_load(data)
    end

    # Transmission parameters
    XLSX.openxlsx(joinpath(dirX, "Transmission.xlsx")) do filehandle
        par.transmissionInitCap = filehandle["InitialCapacity"][:][4:end,:] |> data ->strat_profiles_gen(data)
        par.transmissionMaxBuiltCap = filehandle["MaxBuiltCapacity"][:][4:end,:] |> data ->strat_profiles_gen(data)
        par.transmissionMaxInstalledCap = filehandle["MaxInstallCapacityRaw"][:][4:end,:] |> data ->strat_profiles_gen(data)
        par.transmissionLength = filehandle["Length"][:][4:end,:] |> data ->param_load(data; value_col = 3)
        par.transmissionTypeCapitalCost = filehandle["TypeCapitalCost"][:][4:end,:] |> data ->strat_profiles(data)
        par.transmissionTypeFixedOMCost = filehandle["TypeFixedOMCost"][:][4:end,:] |> data ->strat_profiles(data)
        par.lineEfficiency = filehandle["lineEfficiency"][:][4:end,:] |> data ->param_load(data; value_col = 3)
        par.transmissionLifetime = filehandle["Lifetime"][:][4:end,:] |> data -> param_load(data; value_col = 3)
    end

    # Storage parameters
    XLSX.openxlsx(joinpath(dirX, "Storage.xlsx")) do filehandle
        par.storageBleedEff = data = filehandle["StorageBleedEfficiency"][:][4:end,:] |> data -> param_load(data)
        par.storageChargeEff = data = filehandle["StorageChargeEff"][:][4:end,:] |> data -> param_load(data)
        par.storageDischargeEff = data = filehandle["StorageDischargeEff"][:][4:end,:] |> data -> param_load(data)
        par.storagePowToEnergy = data = filehandle["StoragePowToEnergy"][:][4:end,:] |> data -> param_load(data)
        par.storENCapitalCost = data = filehandle["EnergyCapitalCost"][:][4:end,:] |> data -> strat_profiles(data)
        par.storENFixedOMCost = data = filehandle["EnergyFixedOMCost"][:][4:end,:] |> data -> strat_profiles(data)
        par.storENInitCap = data = filehandle["EnergyInitialCapacity"][:][4:end,:] |> data -> strat_profiles_gen(data)
        par.storENMaxBuiltCap = data = filehandle["EnergyMaxBuiltCapacity"][:][4:end,:] |> data -> strat_profiles_gen(data)
        par.storENMaxInstalledCap = data = filehandle["EnergyMaxInstalledCapacity"][:][4:end,:] |> data -> param_load(data; value_col = 3)
        par.storOperationalInit = data = filehandle["StorageInitialEnergyLevel"][:][4:end,:] |> data -> param_load(data)
        par.storPWCapitalCost = data = filehandle["PowerCapitalCost"][:][4:end,:] |> data -> strat_profiles(data)
        par.storPWFixedOMCost = data = filehandle["PowerFixedOMCost"][:][4:end,:] |> data -> strat_profiles(data)
        par.storPWInitCap = data = filehandle["InitialPowerCapacity"][:][4:end,:] |> data -> strat_profiles_gen(data)
        par.storPWMaxBuiltCap = data = filehandle["PowerMaxBuiltCapacity"][:][4:end,:] |> data -> strat_profiles_gen(data)
        par.storPWMaxInstalledCap = data = filehandle["PowerMaxInstalledCapacity"][:][4:end,:] |> data -> param_load(data; value_col = 3)
        par.storageLifetime = data = filehandle["Lifetime"][:][4:end,:] |> data -> param_load(data)
    end

    # Node parameters
    XLSX.openxlsx(joinpath(dirX, "Node.xlsx")) do filehandle
        par.nodeLostLoadCost = data = filehandle["NodeLostLoadCost"][:][4:end,:] |> data -> strat_profiles(data)
        par.sloadAnnualDemand = data = filehandle["ElectricAnnualDemand"][:][4:end,:] |> data -> strat_profiles(data)
        par.maxRegHydroGenRaw = data = filehandle["HydroGenMaxAnnualProduction"][:][4:end,:] |> data -> param_load(data)
    end

    # General parameters
    XLSX.openxlsx(joinpath(dirX, "General.xlsx")) do filehandle
        par.CO2cap = data = filehandle["CO2Cap"][:][4:end,:] |> data -> strat_profile(data)
        par.CO2price = data = filehandle["CO2Price"][:][4:end,:] |> data -> strat_profile(data)
    end

    return par
end


function read_data_xlsx(dirX)
    # Read the data from the xlsx files

    sets = read_sets_xlsx(dirX)
    par = read_params_xlsx(dirX)

    return (sets, par)
end
