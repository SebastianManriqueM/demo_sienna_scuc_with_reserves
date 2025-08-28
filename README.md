# demo_sienna_scuc_with_reserves
This repo includes different demo scripts of new sienna psy5 functionalities regarding Security-Constrained Unnit commitment formulations.


## Required Packages

To run the scripts in this repository, install the following Julia packages and branches:

- DataFrames v1.7.0
- HiGHS v1.18.2
- HydroPowerSimulations v0.11.1 `https://github.com/NREL-Sienna/HydroPowerSimulations.jl.git#psy5`
- InfrastructureSystems v2.6.0 `https://github.com/NREL-Sienna/InfrastructureSystems.jl.git#main`
- PowerFlows v0.9.0 `https://github.com/NREL-Sienna/PowerFlows.jl.git#psy5`
- PowerNetworkMatrices v0.13.0 `https://github.com/NREL-Sienna/PowerNetworkMatrices.jl.git#psy5
- PowerSimulations v0.30.1 `https://github.com/NREL-Sienna/PowerSimulations.jl.git#jd/sc_models_fixes`
- PowerSystemCaseBuilder v1.3.11 `C:\Users\smachado\repositories\PowerSystemCaseBuilder.jl`
- PowerSystems v4.6.2 `https://github.com/NREL-Sienna/PowerSystems.jl.git#psy5`
- Revise v3.8.0
- TimeSeries v0.24.2
- Dates v1.11.0
- Logging v1.11.0

Make sure to use the specified branches for packages installed from GitHub. The folder "demo_dlr_sienna" contains the .toml files so just activating the enviroment and doing "Pkg.instantiate()" you should get the correct branches.

## REPOS YOU'LL NEED TO CLONE
Please clone `PowerSystemCaseBuilder` and `PowerSystemsTestData` repos. 

Then open `PowerSystemCaseBuilder` and switch to the branch "psy5", in that Branch modify the file "definitions.jl" and change the directory path to PowerSystemsTestData.jl:
```julia
const DATA_DIR =
    joinpath("C:/Users/YOUR_PATH/", "PowerSystemsTestData")
```

## PRINTING YOUR ENVIROMENT SHOULD LOOK LIKE THIS:

```(demo_scuc_sienna) pkg> st
Status `C:\Users\smachado\repositories\demo_sienna_scuc_with_reserves\demo_scuc_sienna\Project.toml`
  [87dc4568] HiGHS v1.19.0
  [2cd47ed4] InfrastructureSystems v2.6.0 `https://github.com/NREL-Sienna/InfrastructureSystems.jl.git#main`
  [94fada2c] PowerFlows v0.9.0 `https://github.com/NREL-Sienna/PowerFlows.jl.git#psy5`
  [bed98974] PowerNetworkMatrices v0.13.0 `https://github.com/NREL-Sienna/PowerNetworkMatrices.jl.git#psy5`
  [e690365d] PowerSimulations v0.30.1 `https://github.com/NREL-Sienna/PowerSimulations.jl.git#jd/sc_models_fixes`
  [f00506e0] PowerSystemCaseBuilder v1.3.11 `C:\Users\smachado\repositories\PowerSystemCaseBuilder.jl`
  [bcd98974] PowerSystems v4.6.2 `https://github.com/NREL-Sienna/PowerSystems.jl.git#psy5`
  [9e3dc215] TimeSeries v0.24.2
  [ade2ca70] Dates v1.11.0
  [56ddb016] Logging v1.11.0
```

# STUDY CASES
This table provides a general overvie of each case study/demo in this repo

| File                                   | System      | Areas | Reserves products                                               |Outage          |
|----------------------------------------|-------------|-------|-----------------------------------------------------------------|----------------|
| simulation_scuc_g-1_reserves_5bus.jl   | IEEE 5-bus  | 1     | Global Up, Global down                                          |1 outage        |
| simulation_scuc_g-1_reserves_RTS.jl    | RTS-GMLC    | 3     | By area sppining up, By area sppining up, Global Up, Global down|1 outage by area|
