# Mathematical model

EMPIRE is a stochastic linear capacity-expansion model. Strategic periods represent investment decisions over a long horizon. Within each strategic period, representative operational seasons, peak hours, and weather/load scenarios represent short-term uncertainty.

## Decisions

The model chooses investment and operation for:

- generation capacity and generator dispatch;
- storage energy and power capacity, charging, discharging, and state of charge;
- transmission capacity and inter-node flows;
- load shedding when demand cannot otherwise be served.

The main JuMP containers are indexed by node, technology, strategic period, and operational time as appropriate. The `TimeStruct.jl` object returned as `periods` defines these indices and their weights.

## Constraints

Constraints enforce demand balance, generation availability, capacity limits, storage dynamics, transmission limits, investment timing, reserve or reliability requirements represented by the input data, and emissions policies. The offshore wind-farm transmission cap is enabled by default.

For out-of-sample operation, completed strategic investments are fixed and investment-only constraints are omitted. This leaves the operational dispatch problem for the supplied scenario tree.

## Objective

The objective minimizes discounted investment and operating costs over the planning horizon. Scenario probabilities and operational duration weights are applied to stochastic operational costs. Emission costs or an emission cap are selected through the run configuration.

The implementation exposes `sol_invest_cost` and `sol_operational_cost` for calculating objective components from a solved JuMP model.

## Time structure

`create_timestruct` constructs strategic periods, regular seasons, peak periods, and scenarios. The configuration controls the horizon, investment-period duration, regular-season length, peak-hour length, number of peak periods, and number of scenarios. Keeping these settings explicit makes representative-period and chronological full-year workflows share the same model formulation.
