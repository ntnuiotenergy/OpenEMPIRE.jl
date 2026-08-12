#!/usr/bin/env python3
"""Regression test for InternalEMPIRE Industry sector-volume certificates."""

from __future__ import annotations

import csv
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from run_internalempire_hydrogen import write_objective_component_certificate


def main() -> None:
    period = 1
    scenario = "scenario1"
    gas_scenario = "gas1"
    hour = 1
    zero_operational = {(period, scenario, gas_scenario): 0.0}
    instance = SimpleNamespace(
        Period=[period],
        Scenario=[scenario],
        GasScenario=[gas_scenario],
        discount_multiplier={period: 1.0},
        sceProbab={scenario: 1.0},
        GasSceProbab={gas_scenario: 1.0},
        GeneratorsOfNode=[],
        StoragesOfNode=[],
        BidirectionalArc=[],
        OffshoreEnergyHubs=[],
        shedcomponent=zero_operational,
        ng_import_cost=zero_operational,
        H2TerminalImportCost=zero_operational,
        reformerOperationalCost=zero_operational,
        steel_opex=zero_operational,
        cement_opex=zero_operational,
        ammonia_opex=zero_operational,
        oil_opex=zero_operational,
        SteelProducers=["N"],
        SteelPlants=["S"],
        SteelPlants_FinalSteel=["S"],
        CementProducers=["N"],
        CementPlants=["C"],
        AmmoniaProducers=["N"],
        AmmoniaPlants=["A"],
        steelPlantBuiltCapacity={("N", "S", period): 0.0},
        cementPlantBuiltCapacity={("N", "C", period): 0.0},
        ammoniaPlantBuiltCapacity={("N", "A", period): 0.0},
        steel_plantInvCost={("S", period): 0.0},
        cement_plantInvCost={("C", period): 0.0},
        ammonia_plantInvCost={("A", period): 0.0},
        OnshoreNode=[],
        transport_naturalGasDemandShed={},
        transport_electricityDemandShed={},
        transport_hydrogenDemandShed={},
        operationalDiscountrate=1.0,
        HoursOfSeason=[("winter", hour)],
        seasScale={"winter": 8760.0},
        transport_curtail_cost=0.0,
        operationalcost={period: 0.0},
        Obj=0.0,
        steelProduced={("N", "S", hour, period, scenario, gas_scenario): 2.0},
        steelLoadShed={("N", hour, period, scenario, gas_scenario): 0.5},
        cementProduced={("N", "C", hour, period, scenario, gas_scenario): 3.0},
        cementLoadShed={("N", hour, period, scenario, gas_scenario): 0.25},
        ammoniaProduced={("N", "A", hour, period, scenario, gas_scenario): 4.0},
        ammoniaLoadShed={("N", hour, period, scenario, gas_scenario): 0.125},
    )

    with TemporaryDirectory() as directory:
        certificate = Path(directory) / "objective_components.csv"
        write_objective_component_certificate(instance, certificate)
        with certificate.open(newline="", encoding="utf-8") as handle:
            values = {
                row["component"]: float(row["value"])
                for row in csv.DictReader(handle)
            }

    expected = {
        "industry_steel_production_volume_period_1": 17520.0,
        "industry_steel_shed_volume_period_1": 4380.0,
        "industry_cement_production_volume_period_1": 26280.0,
        "industry_cement_shed_volume_period_1": 2190.0,
        "industry_ammonia_production_volume_period_1": 35040.0,
        "industry_ammonia_shed_volume_period_1": 1095.0,
    }
    for name, value in expected.items():
        assert values[name] == value, (name, values[name], value)

    print("Industry sector-volume certificate: PASS")


if __name__ == "__main__":
    main()
