"""
GenX: An Configurable Capacity Expansion Model
Copyright (C) 2021,  Massachusetts Institute of Technology
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
A complete copy of the GNU General Public License v2 (GPLv2) is available
in LICENSE.txt.  Users uncompressing this from an archive may not have
received this license file.  If not, see <http://www.gnu.org/licenses/>.
"""

@doc raw"""
	investment_charge!(EP::Model, inputs::Dict)

This function defines the expressions and constraints keeping track of total available storage charge capacity across all resources as well as constraints on capacity retirements. The function also adds investment and fixed O\&M related costs related to charge capacity to the objective function.

The total capacity of each resource is defined as the sum of the existing capacity plus the newly invested capacity minus any retired capacity.

```math
\begin{aligned}
& \Delta^{total,charge}_{y,z} =(\overline{\Delta^{charge}_{y,z}}+\Omega^{charge}_{y,z}-\Delta^{charge}_{y,z}) \forall y \in \mathcal{O}^{asym}, z \in \mathcal{Z}
\end{aligned}
```

One cannot retire more capacity than existing capacity.
```math
\begin{aligned}
&\Delta^{charge}_{y,z} \leq \overline{\Delta^{charge}_{y,z}}
	\hspace{4 cm}  \forall y \in \mathcal{O}^{asym}, z \in \mathcal{Z}
\end{aligned}
```

For resources where $\overline{\Omega_{y,z}^{charge}}$ and $\underline{\Omega_{y,z}^{charge}}$ is defined, then we impose constraints on minimum and maximum power capacity.
```math
\begin{aligned}
& \Delta^{total,charge}_{y,z} \leq \overline{\Omega}^{charge}_{y,z}
	\hspace{4 cm}  \forall y \in \mathcal{O}^{asym}, z \in \mathcal{Z} \\
& \Delta^{total,charge}_{y,z}  \geq \underline{\Omega}^{charge}_{y,z}
	\hspace{4 cm}  \forall y \in \mathcal{O}^{asym}, z \in \mathcal{Z}
\end{aligned}
```

In addition, this function adds investment and fixed O&M related costs related to charge capacity to the objective function:
```math
\begin{aligned}
& 	\sum_{y \in \mathcal{O}^{asym} } \sum_{z \in \mathcal{Z}}
	\left( (\pi^{INVEST,charge}_{y,z} \times    \Omega^{charge}_{y,z})
	+ (\pi^{FOM,charge}_{y,z} \times  \Delta^{total,charge}_{y,z})\right)
\end{aligned}
```
"""
function investment_charge!(EP::Model, inputs::Dict, setup::Dict)

	println("Charge Investment Module")

	dfGen = inputs["dfGen"]
	MultiStage = setup["MultiStage"]

	STOR_ASYMMETRIC = inputs["STOR_ASYMMETRIC"] # Set of storage resources with asymmetric (separte) charge/discharge capacity components

	NEW_CAP_CHARGE = inputs["NEW_CAP_CHARGE"] # Set of asymmetric charge/discharge storage resources eligible for new charge capacity
	RET_CAP_CHARGE = inputs["RET_CAP_CHARGE"] # Set of asymmetric charge/discharge storage resources eligible for charge capacity retirements

	### Variables ###

	## Storage capacity built and retired for storage resources with independent charge and discharge power capacities (STOR=2)

	# New installed charge capacity of resource "y"
	@variable(EP, vCAPCHARGE[y in NEW_CAP_CHARGE] >= 0)

	# Retired charge capacity of resource "y" from existing capacity
	@variable(EP, vRETCAPCHARGE[y in RET_CAP_CHARGE] >= 0)

	if MultiStage == 1
		@variable(EP, vEXISTINGCAPCHARGE[y in STOR_ASYMMETRIC] >= 0);
	end

	### Expressions ###

	if MultiStage == 1
		@expression(EP, eExistingCapCharge[y in STOR_ASYMMETRIC], vEXISTINGCAPCHARGE[y])
	else
		@expression(EP, eExistingCapCharge[y in STOR_ASYMMETRIC], dfGen[y,:Existing_Charge_Cap_MW])
	end

	@expression(EP, eTotalCapCharge[y in STOR_ASYMMETRIC],
		if (y in intersect(NEW_CAP_CHARGE, RET_CAP_CHARGE))
			eExistingCapCharge[y] + EP[:vCAPCHARGE][y] - EP[:vRETCAPCHARGE][y]
		elseif (y in setdiff(NEW_CAP_CHARGE, RET_CAP_CHARGE))
			eExistingCapCharge[y] + EP[:vCAPCHARGE][y]
		elseif (y in setdiff(RET_CAP_CHARGE, NEW_CAP_CHARGE))
			eExistingCapCharge[y] - EP[:vRETCAPCHARGE][y]
		else
			eExistingCapCharge[y] + EP[:vZERO]
		end
	)

	## Objective Function Expressions ##

    # Fixed costs for resource "y" = annuitized investment cost plus fixed O&M costs
    # If resource is not eligible for new charge capacity, fixed costs are only O&M costs
    @expression(EP, eCInvChargeCap[y in STOR_ASYMMETRIC],
        if y in NEW_CAP_CHARGE # Resources eligible for new charge capacity
            dfGen[y, :Inv_Cost_Charge_per_MWyr] * EP[:vCAPCHARGE][y]
        else
            EP[:vZERO]
        end
    )
    @expression(EP, eCFOMChargeCap[y in STOR_ASYMMETRIC], dfGen[y, :Fixed_OM_Cost_Charge_per_MWyr] * eTotalCapCharge[y])
    @expression(EP, eCFixCharge[y in STOR_ASYMMETRIC], EP[:eCInvChargeCap][y] + EP[:eCFOMChargeCap][y])
    # Sum individual resource contributions to fixed costs to get total fixed costs
    @expression(EP, eZonalCFOMChargeCap[z = 1:Z], EP[:vZERO] + sum(EP[:eCFOMChargeCap][y] for y in intersect(STOR_ASYMMETRIC, dfGen[(dfGen[!, :Zone].==z), :R_ID])))
    @expression(EP, eZonalCInvChargeCap[z = 1:Z], EP[:vZERO] + sum(EP[:eCInvChargeCap][y] for y in intersect(STOR_ASYMMETRIC, dfGen[(dfGen[!, :Zone].==z), :R_ID])))
    @expression(EP, eZonalCFixCharge[z = 1:Z], EP[:vZERO] + sum(EP[:eCFixCharge][y] for y in intersect(STOR_ASYMMETRIC, dfGen[(dfGen[!, :Zone].==z), :R_ID])))

    @expression(EP, eTotalCFOMCharge, sum(EP[:eZonalCFOMChargeCap][z] for z in 1:Z))
    @expression(EP, eTotalCInvCharge, sum(EP[:eZonalCInvChargeCap][z] for z in 1:Z))
    @expression(EP, eTotalCFixCharge, sum(EP[:eZonalCFixCharge][z] for z in 1:Z))

	# Add term to objective function expression
	if MultiStage == 1
		# OPEX multiplier scales fixed costs to account for multiple years between two model stages
		# We divide by OPEXMULT since we are going to multiply the entire objective function by this term later,
		# and we have already accounted for multiple years between stages for fixed costs.
		EP[:eObj] += (1/inputs["OPEXMULT"])*eTotalCFixCharge
	else
		EP[:eObj] += eTotalCFixCharge
	end

	### Constratints ###

	if MultiStage == 1
		# Existing capacity variable is equal to existing capacity specified in the input file
		@constraint(EP, cExistingCapCharge[y in STOR_ASYMMETRIC], EP[:vEXISTINGCAPCHARGE][y] == dfGen[y,:Existing_Charge_Cap_MW])
	end

	## Constraints on retirements and capacity additions
	#Cannot retire more charge capacity than existing charge capacity
	@constraint(EP, cMaxRetCharge[y in RET_CAP_CHARGE], vRETCAPCHARGE[y] <= eExistingCapCharge[y])

  	#Constraints on new built capacity

	# Constraint on maximum charge capacity (if applicable) [set input to -1 if no constraint on maximum charge capacity]
	# DEV NOTE: This constraint may be violated in some cases where Existing_Charge_Cap_MW is >= Max_Charge_Cap_MWh and lead to infeasabilty
	@constraint(EP, cMaxCapCharge[y in intersect(dfGen[!,:Max_Charge_Cap_MW].>0, STOR_ASYMMETRIC)], eTotalCapCharge[y] <= dfGen[y,:Max_Charge_Cap_MW])

	# Constraint on minimum charge capacity (if applicable) [set input to -1 if no constraint on minimum charge capacity]
	# DEV NOTE: This constraint may be violated in some cases where Existing_Charge_Cap_MW is <= Min_Charge_Cap_MWh and lead to infeasabilty
	@constraint(EP, cMinCapCharge[y in intersect(dfGen[!,:Min_Charge_Cap_MW].>0, STOR_ASYMMETRIC)], eTotalCapCharge[y] >= dfGen[y,:Min_Charge_Cap_MW])

end
