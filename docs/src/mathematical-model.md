# Mathematical model

EMPIRE is a stochastic linear capacity-expansion model. Strategic periods represent investment decisions over a long horizon. Within each strategic period, representative operational seasons, peak hours, and weather/load scenarios represent short-term uncertainty.

## Sets

### Spatial and Network Sets

| Symbol | Description |
|----------|-------------|
| N | Set of nodes (regions, countries, offshore areas, or hubs) |
| A | Set of directed transmission links (arcs) |
| C | Set of transmission corridors (undirected connections) |
| T_trans | Set of transmission technology types |

### Temporal Sets

| Symbol | Description |
|----------|-------------|
| P | Set of strategic (investment) periods |
| R | Set of representative periods (seasons) |
| R_season | Set of regular seasonal representative periods |
| R_peak | Set of peak representative periods |
| H_r | Set of operational hours in representative period r |
| T | Set of all operational timesteps |
| Ω | Set of operational scenarios |

#### Time structure

`create_timestruct` constructs strategic periods, regular seasons, peak periods, and scenarios. The configuration controls the horizon, investment-period duration, regular-season length, peak-hour length, number of peak periods, and number of scenarios. Keeping these settings explicit makes representative-period and chronological full-year workflows share the same model formulation.

### Generator Sets

| Symbol | Description |
|----------|-------------|
| G | Set of generators |
| G_thermal | Set of thermal generators |
| G_hydro | Set of hydro generators |
| G_reg | Set of regulated hydro generators |

The generator subsets satisfy:

- G_reg ⊆ G_hydro
- G_thermal ∩ G_hydro = ∅

### Storage Sets

| Symbol | Description |
|----------|-------------|
| S | Set of storage technologies |
| S_dep | Set of dependent storage technologies |

Dependent storage technologies have their energy capacity linked to their installed power capacity.

### Technology Sets

| Symbol | Description |
|----------|-------------|
| K | Set of technology categories |

Technology categories are used to group generators into common technology classes.

### Offshore Node Sets

| Symbol | Description |
|----------|-------------|
| N_OWF | Set of offshore wind farm nodes |
| N_Hub | Set of offshore energy hub nodes |

The offshore node sets are disjoint:

- N_OWF ∩ N_Hub = ∅

### Relational Sets

| Symbol | Description |
|----------|-------------|
| NG | Set of node-generator pairs (n,g) |
| NS | Set of node-storage pairs (n,s) |
| KG | Set of technology-generator pairs (k,g) |

### Derived Sets

The following derived sets are constructed from the relational sets.

| Symbol | Description |
|----------|-------------|
| G_n | Generators located at node n |
| S_n | Storage technologies located at node n |
| K_n | Technology categories represented at node n |
| G_n,k | Generators at node n that belong to technology category k |

### Transmission Mapping

| Symbol | Description |
|----------|-------------|
| (a,τ) ∈ A_trans | Transmission technology τ assigned to arc a |

### Additional Notes

- Each generator belongs to at least one technology category.
- Each generator is assigned to at least one node.
- Each transmission arc may be assigned one transmission technology type.
- Offshore wind farm nodes must contain at least one generator.
- Offshore energy hub nodes and offshore wind farm nodes represent different physical concepts and cannot overlap.

## Parameters

Notation uses the indices defined in the Sets section:

- n ∈ N: node 
- m,n ∈ C: transmission corridor (node pair) 
- g ∈ G: generator
- s ∈ S: storage technology
- k ∈ K: technology category
- p ∈ P: strategic period
- h ∈ H: operational hour
- ω ∈ Ω: operational scenario

### Financial Parameters

| Symbol | Description | Unit |
|----------|-------------|------|
| r | Discount rate | - |
| WACC | Weighted average cost of capital | - |

### Representative Period Scaling Parameters

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| M_h | h | Number of physical hours represented by operational hour h | hours |
| μ_h,p | h,p | Strategic-period scaling factor | - |
| π_ω | ω | Probability of operational scenario ω | - |
| δ_p | p | Discount factor applied to strategic period p | - |
 
The strategic-period scaling factor is defined as:

```text
μ_h,p = M_h / Y_p
```
### Generator Parameters

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| C_g,p_inv | g,p | Investment cost | EUR/MW |
| C_g,p_marg | g,p | Marginal generator cost | EUR/MWh |
| eta_g,p | g,p | Efficiency | - |
| rho_g | g | Ramp-up limit | - |
| A_n,g,h,ω,p | n,g,h,ω,p | Availability factor | - |
| E_g_CO2 | g | CO2 emission factor | tCO2/MWh_fuel |
| L_g | g | Lifetime | years |

### Generator Capacity Parameters

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| K_n,g,p_init | n,g,p | Initial installed capacity | MW |
| K_n,g,p_build,max | n,g,p | Maximum build capacity (in single inv period p) | MW |
| K_n,g,p_inst,max | n,g,p | Maximum installed capacity (in any inv period p) | MW |

### Transmission Parameters

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| F_m,n,p_init | m,n,p | Initial transmission capacity | MW |
| F_m,n,p_build,max | m,n,p | Maximum transmission expansion (in single inv period p) | MW |
| F_m,n,p_inst,max | m,n,p | Maximum installed transmission capacity (in any inv period p) | MW |
| eta_m,n | m,n | Transmission efficiency | - |
| l_m,n | m,n | Line length | km |
| C_m,n_inv | m,n | Investment cost | EUR/MW |
| C_m,n_fix | m,n | Fixed O&M cost | EUR/MW/year |
| L_m,n | m,n | Lifetime | years |

### Storage Parameters

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| eta_s_ch | s | Charging efficiency | - |
| eta_s_dis | s | Discharging efficiency | - |
| eta_s_bleed | s | Retention (self-discharge) efficiency | - |
| alpha_s | s | Power-to-energy ratio | h^-1 |
| beta_s | s | Discharge-to-charge ratio | - |
| L_s | s | Lifetime | years |

### Demand and Resource Parameters

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| D_n,h,ω,p | n,h,ω,p | Electricity demand | MW |
| C_n_LL | n | Value of lost load | EUR/MWh |
| G_n,ω,p_hyd,max | n,ω,p | Maximum regulated hydro generation | MWh |
| CAP_p_CO2 | p | CO2 emissions cap | tCO2 |
| P_p_CO2 | p | CO2 price | EUR/tCO2 |

## Derived Parameters

Several parameters used in the optimization model are derived during preprocessing from the raw input data. These derived parameters are the quantities that appear directly in the objective function and constraints.

### Additional Symbols
The following symbols are used only in the derivation of processed parameters and do not appear directly in the optimization model.

| Symbol | Description | Unit |
|----------|-------------|------|
| CAPEX_g(p) | Capital expenditure of generator g | EUR/MW |
| CAPEX_s_EN(p) | Capital expenditure of storage energy capacity | EUR/MWh |
| CAPEX_s_PW(p) | Capital expenditure of storage power capacity | EUR/MW |
| CAPEX_m,n(p) | Capital expenditure of transmission capacity | EUR/(MW·km) |
| CAPEX_hub(p) | Capital expenditure of offshore converter capacity | EUR/MW |
| FOM_g(p) | Fixed O&M cost of generator g | EUR/MW/year |
| FOM_s_EN(p) | Fixed O&M cost of storage energy capacity | EUR/MWh/year |
| FOM_s_PW(p) | Fixed O&M cost of storage power capacity | EUR/MW/year |
| FOM_m,n(p) | Fixed O&M cost of transmission capacity | EUR/(MW·km·year) |
| FOM_hub(p) | Fixed O&M cost of offshore converter capacity | EUR/MW/year |
| C_g_fuel(p) | Fuel cost of generator g | EUR/GJ |
| C_g_var(p) | Variable O&M cost of generator g | EUR/MWh |
| Y_a(p) | Remaining active lifetime of asset a within the planning horizon | years |
| AF_a | Annuity factor for asset a | years |
| PV(AC,Y) | Present value of a stream of annual payments | EUR |
| CCS_g(p) | Additional CCS transport and storage investment cost associated with generator g | EUR/MW |
| C_CCS_var(p) | Variable CCS transport and storage cost | EUR/tCO₂ |
| r_CCS | CO₂ capture rate for CCS generators | - |

### Financial Factors

#### Annuity Factor

The annuity factor converts an upfront investment cost into an equivalent annual payment over the lifetime of an asset.

```text
AF_a = (1 - (1 + WACC)^(-L_a)) / WACC
```

| Symbol | Description | Unit |
|----------|-------------|------|
| WACC | Weighted average cost of capital | - |
| L_a | Lifetime of asset a | years |
| AF_a | Annuity factor | years |

#### Present Value Factor

The present value of an annual payment stream is calculated as:

```text
PV(AC,Y) = AC · (1-(1+r)^(-Y))/r
```

| Symbol | Description | Unit |
|----------|-------------|------|
| AC | Annual cost | EUR/year |
| r | Discount rate | - |
| Y | Remaining active years | years |

Investments are assumed to occur at the beginning of each strategic period.

### Derived Investment Cost Parameters

#### Generator Investment Cost

```text
C_g_inv(p)
=
PV(
CAPEX_g(p)/AF_g
+
FOM_g(p),
Y_g(p)
)
+
CCS_g(p)
```

| Symbol | Description | Unit |
|----------|-------------|------|
| C_g_inv(p) | Discounted lifecycle investment cost | EUR/MW |
| Y_g(p) | Remaining active years for generator g in period p | years |

#### Storage Energy-Capacity Investment Cost

```text
C_s_EN_inv(p)
=
PV(
CAPEX_s_EN(p)/AF_s
+
FOM_s_EN(p),
Y_s(p)
)
```

| Symbol | Description | Unit |
|----------|-------------|------|
| C_s_EN_inv(p) | Investment cost of storage energy capacity | EUR/MWh |

#### Storage Power-Capacity Investment Cost

```text
C_s_PW_inv(p)
=
PV(
CAPEX_s_PW(p)/AF_s
+
FOM_s_PW(p),
Y_s(p)
)
```

| Symbol | Description | Unit |
|----------|-------------|------|
| C_s_PW_inv(p) | Investment cost of storage power capacity | EUR/MW |

#### Transmission Investment Cost

```text
C_m,n_inv(p)
=
PV(
l_m,n
(
CAPEX_m,n(p)/AF_m,n
+
C_m,n_fix(p)
),
Y_m,n(p)
)
```

| Symbol | Description | Unit |
|----------|-------------|------|
| C_m,n_inv(p) | Discounted lifecycle cost of transmission capacity | EUR/MW |

#### Offshore Converter Investment Cost

```text
C_hub_inv(p)
=
PV(
CAPEX_hub(p)/AF_hub
+
FOM_hub(p),
Y_hub(p)
)
```

| Symbol | Description | Unit |
|----------|-------------|------|
| C_hub_inv(p) | Offshore converter investment cost | EUR/MW |

---

### Derived Operational Cost Parameters

#### Generator Marginal Cost

For conventional generators:

```text
C_g,p_marg
=
(3.6/eta_g,p)
(
C_g_fuel(p)
+
P_p_CO2 E_g_CO2
)
+
C_g_var(p)
```

For CCS generators:

```text
C_g_marg(p)
=
(3.6/eta_g(p))
(
C_g_fuel(p)
+
(1-r_CCS) P_p_CO2 E_g_CO2
+
r_CCS C_CCS_var(p) E_g_CO2
)
+
C_g_var(p)
```

with default:

```text
r_CCS = 0.9
```

| Symbol | Description | Unit |
|----------|-------------|------|
| C_g,p_marg | Marginal generation cost | EUR/MWh |

---

### Derived Demand Parameter

Raw load profiles are scaled such that modeled annual demand equals the specified annual demand.

| Symbol | Description | Unit |
|----------|-------------|------|
| D_n,h,ω,p | Electricity demand used in the optimization model | MW |

---

### Derived Hydro Parameter

Hydrological profiles are aggregated to representative periods and operational scenarios.

| Symbol | Description | Unit |
|----------|-------------|------|
| G_n,ω,p_hyd,max | Maximum regulated hydro generation | MWh |

---

### Adjusted Capacity Limits

Maximum installed capacity limits are adjusted whenever the specified initial capacity exceeds the user-defined upper bound.

#### Generator Technologies

```text
K_n,g,p_inst,max = max(K_n,g,p_inst,max, K_n,g,p_init)
```

#### Transmission Corridors

```text
F_m,n,p_inst,max = max(F_m,n,p_inst,max, F_m,n,p_init)
```

This guarantees that all existing infrastructure remains feasible in the optimization model.

## Decision Variables

The model chooses investment and operation for:

- generation capacity and generator dispatch;
- storage energy and power capacity, charging, discharging, and state of charge;
- transmission capacity and inter-node flows;
- load shedding when demand cannot otherwise be served.

The main JuMP containers are indexed by node, technology, strategic period, and operational time as appropriate. The `TimeStruct.jl` object returned as `periods` defines these indices and their weights.

### Generator Capacity Variables

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| x_gen(n,g,p) | n,g,p | New generator capacity investment in strategic period p | MW |
| K_gen(n,g,p) | n,g,p | Installed generator capacity available in strategic period p | MW |

### Transmission Capacity Variables

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| x_trans(m,n,p) | m,n,p | New transmission capacity investment | MW |
| F(m,n,p) | m,n,p | Installed transmission capacity | MW |

### Offshore Energy Hub Variables

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| x_hub(n,p) | n,p | New offshore converter capacity investment | MW |
| H_hub(n,p) | n,p | Installed offshore converter capacity | MW |

Defined only for offshore energy hub nodes n ∈ N_Hub.

### Storage Capacity Variables

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| x_pow(n,s,p) | n,s,p | New storage power-capacity investment | MW |
| P(n,s,p) | n,s,p | Installed storage power capacity | MW |
| x_en(n,s,p) | n,s,p | New storage energy-capacity investment | MWh |
| E(n,s,p) | n,s,p | Installed storage energy capacity | MWh |

### Generation Dispatch Variables

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| g(n,g,h,ω,p) | n,g,h,ω,p | Electricity generation output | MW |

### Transmission Flow Variables

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| f(m,n,h,ω,p) | m,n,h,ω,p | Power flow between nodes | MW |

### Storage Operation Variables

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| c(n,s,h,ω,p) | n,s,h,ω,p | Storage charging rate | MW |
| d(n,s,h,ω,p) | n,s,h,ω,p | Storage discharging rate | MW |
| soc(n,s,h,ω,p) | n,s,h,ω,p | State of charge | MWh |

### Reliability Variables

| Symbol | Index | Description | Unit |
|----------|----------|-------------|------|
| ls(n,h,ω,p) | n,h,ω,p | Unserved electricity demand (load shedding) | MW |

### Variable Domains

| Variable | Domain |
|----------|----------|
| x_gen, K_gen | ≥ 0 |
| x_trans, F | ≥ 0 |
| x_hub, H_hub | ≥ 0 |
| x_pow, P | ≥ 0 |
| x_en, E | ≥ 0 |
| g | ≥ 0 |
| f | ≥ 0 |
| c | ≥ 0 |
| d | ≥ 0 |
| soc | ≥ 0 |
| ls | ≥ 0 |

## Objective

The objective minimizes discounted investment and operating costs over the planning horizon. Scenario probabilities and operational duration weights are applied to stochastic operational costs. Emission costs or an emission cap are selected through the run configuration.

The implementation exposes `sol_invest_cost` and `sol_operational_cost` for calculating objective components from a solved JuMP model.

Investment costs are discounted financial costs, while energy-not-served
metrics from out-of-sample aggregation are physical, probability-weighted
energy and are not discounted. The annuity/present-value calculation remains a
documented difference under investigation; see [TODO.md](https://github.com/ntnuiotenergy/OpenEMPIRE.jl/blob/main/TODO.md).

The objective function consists of six cost components:

1. Generator investment costs
2. Storage investment costs
3. Transmission investment costs
4. Offshore energy hub converter investment costs
5. Generator operating costs
6. Load shedding costs

The optimization problem is:

```text
min Z
```

where

```text
Z = C_gen_inv + C_stor_inv + C_trans_inv + C_hub_inv + C_gen_op + C_shed
```

### Generator Investment Cost

```text
C_gen_inv
=
Σ_p δ_p
Σ_n
Σ_{g∈G_n}
C_g_inv(p)
·
x_gen(n,g,p)
```

| Symbol | Description | Unit |
|----------|-------------|------|
| x_gen(n,g,p) | New generator capacity investment | MW |
| C_g_inv(p) | Processed generator investment cost | EUR/MW |
| δ_p | Discount factor for strategic period p | - |

---

### Storage Investment Cost

```text
C_stor_inv
=
Σ_p δ_p
Σ_n
Σ_{s∈S_n}
[
C_s_PW_inv(p)·x_pow(n,s,p)
+
C_s_EN_inv(p)·x_en(n,s,p)
]
```

| Symbol | Description | Unit |
|----------|-------------|------|
| x_pow(n,s,p) | New storage power-capacity investment | MW |
| x_en(n,s,p) | New storage energy-capacity investment | MWh |
| C_s_PW_inv(p) | Processed storage power-capacity investment cost | EUR/MW |
| C_s_EN_inv(p) | Processed storage energy-capacity investment cost | EUR/MWh |

---

### Transmission Investment Cost

```text
C_trans_inv
=
Σ_p δ_p
Σ_{(m,n)∈C}
C_m,n_inv(p)
·
x_trans(m,n,p)
```

| Symbol | Description | Unit |
|----------|-------------|------|
| x_trans(m,n,p) | New transmission capacity investment | MW |
| C_m,n_inv(p) | Processed transmission investment cost | EUR/MW |

Transmission investments are defined on transmission corridors.

---

### Offshore Energy Hub Investment Cost

```text
C_hub_inv
=
Σ_p δ_p
Σ_{n∈N_Hub}
C_hub_inv(p)
·
x_hub(n,p)
```

| Symbol | Description | Unit |
|----------|-------------|------|
| x_hub(n,p) | New offshore converter capacity investment | MW |
| C_hub_inv(p) | Processed offshore converter investment cost | EUR/MW |

---

### Generator Operating Cost

```text
C_gen_op
=
Σ_p
δ_p
Σ_ω
π_ω
Σ_h
μ_h,p
Σ_n
Σ_{g∈G_n}
C_g_marg(p)
·
g(n,g,h,ω,p)
```

| Symbol | Description | Unit |
|----------|-------------|------|
| g(n,g,h,ω,p) | Generator dispatch | MW |
| C_g_marg(p) | Processed marginal generation cost | EUR/MWh |
| w_h,ω,p | Representative-period weight | - |

The marginal generation cost combines fuel costs, variable O&M costs, CO₂ costs, CCS costs, and generator efficiency effects through preprocessing.

---

### Load Shedding Cost

```text
C_shed
=
Σ_p
δ_p
Σ_ω
π_ω
Σ_h
μ_h,p
Σ_n
C_n_LL
·
ls(n,h,ω,p)
```

| Symbol | Description | Unit |
|----------|-------------|------|
| ls(n,h,ω,p) | Load shedding | MW |
| C_n_LL | Value of lost load | EUR/MWh |

Load shedding is penalized through a high value of lost load in order to discourage unserved demand.

---

## Constraints

Constraints enforce demand balance, generation availability, capacity limits, storage dynamics, transmission limits, investment timing, reserve or reliability requirements represented by the input data, and emissions policies. The offshore wind-farm transmission cap is enabled by default.

The wind-farm cap is created after investment-only constraints and is therefore
omitted when strategic capacities are fixed for out-of-sample operation. The
offshore energy-hub converter formulation is not implemented; hubs are read
and validated but do not yet receive their own capacity limit.

For out-of-sample operation, completed strategic investments are fixed and investment-only constraints are omitted. This leaves the operational dispatch problem for the supplied scenario tree.

