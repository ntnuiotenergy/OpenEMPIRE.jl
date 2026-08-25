using Pkg
Pkg.activate(@__DIR__)

using Documenter
using OpenEMPIRE

makedocs(
    sitename = "OpenEMPIRE.jl",
    authors = "OpenEMPIRE contributors",
    modules = [OpenEMPIRE],
    checkdocs = :none,
    clean = false,
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        assets = String[],
    ),
    build = joinpath(@__DIR__, "build-clean"),
    pages = [
        "Home" => "index.md",
        "User guide" => [
            "Running the model" => "user-guide.md",
            "Input data" => "input-data.md",
            "Scenarios and out-of-sample" => "scenarios.md",
            "Mathematical model" => "mathematical-model.md",
        ],
        "API reference" => "api.md",
        "Contributing" => "contributing.md",
    ],
)

if get(ENV, "GITHUB_ACTIONS", nothing) == "true"
    deploydocs(repo = "github.com/ntnuiotenergy/OpenEMPIRE.jl.git")
end
