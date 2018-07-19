package org.eclipse.mita.base.typesystem.constraints

import org.eclipse.mita.base.typesystem.types.AbstractType
import org.eclipse.mita.base.typesystem.types.TypeVariable
import org.eclipse.xtend.lib.annotations.EqualsHashCode
import org.eclipse.xtend.lib.annotations.FinalFieldsConstructor
import org.eclipse.xtend.lib.annotations.Accessors

@FinalFieldsConstructor 
@Accessors
@EqualsHashCode
class Equality extends AbstractTypeConstraint {
	protected final AbstractType left;
	protected final AbstractType right;

	override toString() {
		left + " ≡ " + right
	}
	
	override replace(TypeVariable from, AbstractType with) {
		return new Equality(left.replace(from, with), right.replace(from, with));
	}
	
	override getActiveVars() {
		return left.freeVars + right.freeVars;
	}
	
	override getOrigins() {
		return #[left, right].map[ it.origin ];
	}

}