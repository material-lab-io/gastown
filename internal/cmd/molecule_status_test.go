package cmd

import (
	"testing"
)

// TestOutputMoleculeStatus_StandaloneFormulaShowsVars was testing fields
// (AttachedFormula, AttachedVars) that were removed from MoleculeStatusInfo.
// Tracked for re-implementation in gt-47o.
func TestOutputMoleculeStatus_StandaloneFormulaShowsVars(t *testing.T) {
	t.Skip("pending gt-47o: AttachedFormula/AttachedVars removed from MoleculeStatusInfo")
}

// TestOutputMoleculeStatus_FormulaWispShowsWorkflowContext was testing fields
// (AttachedFormula) that were removed from MoleculeStatusInfo.
// Tracked for re-implementation in gt-47o.
func TestOutputMoleculeStatus_FormulaWispShowsWorkflowContext(t *testing.T) {
	t.Skip("pending gt-47o: AttachedFormula removed from MoleculeStatusInfo")
}
