const RESULT_SERIES_COLORS = Dict(
    "Bio" => "#2ca02c",
    "Bio cofiring" => "#8c564b",
    "Bio cofiring CCS" => "#6b8e23",
    "Coal" => "#4d4d4d",
    "Coal CCS" => "#7f7f7f",
    "Gas" => "#bc6c25",
    "Gas CCS" => "#dda15e",
    "Geothermal" => "#9467bd",
    "Hydro regulated" => "#1f77b4",
    "Hydro run-of-river" => "#17becf",
    "Lignite" => "#6c584c",
    "Lignite CCS" => "#a98467",
    "Nuclear" => "#d62728",
    "Oil" => "#111111",
    "Solar" => "#ffbf00",
    "Waste" => "#8c564b",
    "Wave" => "#2b8cbe",
    "Wind offshore" => "#6baed6",
    "Wind onshore" => "#74c476",
    "HydroPumpStorage" => "#1f77b4",
    "Li-Ion_BESS" => "#ff7f0e",
    "CCS" => "#7f7f7f",
    "Existing" => "#9e9e9e",
    # Non-generation bands of the hourly dispatch stack. Storage is deliberately
    # violet rather than orange: "Gas" is #bc6c25, and an orange storage pair made
    # the large negative charging band read as gas at a glance.
    "Storage discharge" => "#9d5cd6",
    "Storage charge" => "#6a3d9a",
    "Import" => "#76b7b2",
    "Export" => "#4a7c7a",
    "Load shed" => "#e31a1c",
    "Transmission losses" => "#b0b0b0",
)

const TRANSMISSION_TYPE_COLORS = Dict(
    "HVAC_OverheadLine" => "#32213A",
    "HVDC_Cable" => "#2E86AB",
)
