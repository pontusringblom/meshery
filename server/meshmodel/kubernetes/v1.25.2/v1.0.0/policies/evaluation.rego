package relationship_evaluation_policy

import rego.v1

default rels_in_design_file := []

rels_in_design_file := input.relationships if {
	count(input.relationships) > 0
}

filter_pending_relationships(rel, relationships) := rel if {
	every relationship in relationships {
		relationship.id == rel.id
	}
}

evaluate := eval_results if {
	# iterate relationships in the design file and resolve the patches.
	resultant_patches := {patched_object |
		some rel in rels_in_design_file

		# do not evaluate relationships which have status as "deleted".
		lower(rel.status) == "pending"

		resultant_patch := perform_eval(input, rel)

		# change status for pending relationship
		r = json.patch(rel, [{
			"op": "replace",
			"path": "/status",
			"value": "approved",
		}])

		patched_object := {
			"patches": resultant_patch,
			"relationship": r,
		}
	}

	intermediate_rels := [relationship |
		some val in resultant_patches
		relationship := val.relationship
	]

	updated_pending_rels := [rel |
		some relationship in rels_in_design_file
		rel := filter_relationship(relationship, intermediate_rels)
	]

	# separate out same declarations by id.
	intermediate_result := {x |
		some val in resultant_patches
		some nval in val.patches
		x := nval
	}

	# assign id for new identified rels
	ans := group_by_id(intermediate_result)

	result := {mutated |
		some val in ans
		mutated_declaration := json.patch(val.declaration, val.patches)
		mutated := {
			"declaration_id": mutated_declaration.id,
			"declaration": mutated_declaration,
		}
	}

	design_file_with_updated_declarations := [declaration |
		some val in input.components

		declaration := filter_updated_declaration(val, result)
	]

	updated_declarations := [decl |
		some obj in result
		decl := obj.declaration
	]
	# all pending relationships are now resolved.
	updated_design_file := json.patch(input, [{
		"op": "replace",
		"path": "/components",
		"value": design_file_with_updated_declarations,
	}])

	updated_relationships := union({result |
		# relationships from registry
		some relationship in data.relationships
		result := identify_relationship(updated_design_file, relationship)
	})

	# the evaluate_relationships_added rule can work on the orignal deisng or the updated design.
	# because it is concerned only about relationships which is not changed uptil this point.

	relationships_added := evaluate_relationships_added(updated_pending_rels, updated_relationships)

	relationships_deleted := evaluate_relationships_deleted(updated_pending_rels, updated_relationships)

	final_rels_added := array.concat(updated_pending_rels, relationships_added)

	final_rels_with_deletions := [rel |
		some relationship in final_rels_added
		rel := filter_relationship(relationship, relationships_deleted)
	]

	final_design_file = json.patch(updated_design_file, [{
		"op": "add",
		"path": "/relationships",
		"value": final_rels_with_deletions,
	}])

	eval_results := {
		"design": final_design_file,
		"trace": {
			"componentsUpdated": updated_declarations,
			"relationshipsAdded": relationships_added,
			"relationshipsRemoved": relationships_deleted,
		},
	}
}

filter_updated_declaration(declaration, updated_declarations) := obj.declaration if {
	some obj in updated_declarations
	obj.declaration_id == declaration.id
} else := declaration

filter_relationship(rel, relationships) := relationship if {
	some relationship in relationships
	relationship.id == rel.id
} else := rel
