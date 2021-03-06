/********************************************************************************
 * Copyright (c) 2018, 2019 Robert Bosch GmbH & TypeFox GmbH
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License 2.0 which is available at
 * http://www.eclipse.org/legal/epl-2.0.
 *
 * Contributors:
 *    Robert Bosch GmbH & TypeFox GmbH - initial contribution
 *
 * SPDX-License-Identifier: EPL-2.0
 ********************************************************************************/

package org.eclipse.mita.base.typesystem.infra

import org.eclipse.emf.common.notify.impl.AdapterImpl
import org.eclipse.emf.ecore.EObject
import org.eclipse.mita.base.typesystem.types.AbstractType
import org.eclipse.xtend.lib.annotations.FinalFieldsConstructor

@FinalFieldsConstructor
class TypeAdapter extends AdapterImpl {
	protected final AbstractType type;
	
	static def void set(EObject obj, AbstractType type) {
		obj.eAdapters.add(new TypeAdapter(type));
	}
	
	static def AbstractType get(EObject obj) {
		return obj?.eAdapters?.filter(TypeAdapter)?.head?.type;
	}
	
	public override toString() {
		return '''TypeAdapter: «type»''';
	}
	
}