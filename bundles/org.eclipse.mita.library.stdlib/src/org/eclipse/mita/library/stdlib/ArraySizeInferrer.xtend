/********************************************************************************
 * Copyright (c) 2017, 2018 Bosch Connected Devices and Solutions GmbH.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License 2.0 which is available at
 * http://www.eclipse.org/legal/epl-2.0.
 *
 * Contributors:
 *    Bosch Connected Devices and Solutions GmbH - initial contribution
 *
 * SPDX-License-Identifier: EPL-2.0
 ********************************************************************************/

package org.eclipse.mita.library.stdlib

import com.google.inject.Inject
import org.eclipse.mita.base.expressions.ElementReferenceExpression
import org.eclipse.mita.base.expressions.ValueRange
import org.eclipse.mita.base.expressions.util.ExpressionUtils
import org.eclipse.mita.base.types.Operation
import org.eclipse.mita.base.types.typesystem.ITypeSystem
import org.eclipse.mita.base.typesystem.StdlibTypeRegistry
import org.eclipse.mita.base.typesystem.types.TypeConstructorType
import org.eclipse.mita.base.util.BaseUtils
import org.eclipse.mita.program.ArrayLiteral
import org.eclipse.mita.program.NewInstanceExpression
import org.eclipse.mita.program.inferrer.ElementSizeInferrer
import org.eclipse.mita.program.inferrer.InvalidElementSizeInferenceResult
import org.eclipse.mita.program.inferrer.StaticValueInferrer
import org.eclipse.mita.program.inferrer.ValidElementSizeInferenceResult
import org.eclipse.mita.base.typesystem.types.AbstractType
import static extension org.eclipse.mita.base.types.TypesUtil.ignoreCoercions

class ArraySizeInferrer extends ElementSizeInferrer {
	
	@Inject
    protected ITypeSystem registry;
	
	
	override protected dispatch doInfer(NewInstanceExpression obj, AbstractType type) {
		val parentType = BaseUtils.getType(obj.eContainer);
		
		val rawSizeValue = ExpressionUtils.getArgumentValue(obj.reference as Operation, obj, 'size');
		if(rawSizeValue === null) {
			return new InvalidElementSizeInferenceResult(obj, parentType, "size missing");
		} else if(parentType === null) {
			return new InvalidElementSizeInferenceResult(obj, parentType, "parent type unknown");
		} else {
			val staticSizeValue = StaticValueInferrer.infer(rawSizeValue, [x |]);
			val result = if(staticSizeValue === null) {
				newInvalidResult(obj.reference, "Cannot infer static value");
			} else {
				// lets assume that no one constructs arrays bigger than Integer.MAX_VALUE
				new ValidElementSizeInferenceResult(obj, parentType, (staticSizeValue as Long).longValue as int);
			}
			
			/**
			 * TODO: at the moment we don't have array/struct literals. As such the size inference for arrays
			 * is limited to primitive types, because the size of generated types is determined during initialization.
			 */
			val typeOfChildren = (parentType as TypeConstructorType).typeArguments.tail.head;
			result.children.add(obj.inferFromType(typeOfChildren));
			return result;
		}
	}
	
	def protected dispatch doInfer(ArrayLiteral obj, AbstractType type) {
		val parentType = BaseUtils.getType(obj.eContainer);
		
		val typeOfChildren = (parentType as TypeConstructorType).typeArguments.tail.head;
		
		val result = new ValidElementSizeInferenceResult(obj, parentType, obj.values.length);
		 
		if(typeOfChildren.name == StdlibTypeRegistry.arrayTypeQID.lastSegment) {
			result.children.add(infer(obj.values.head));	
		}
		else {
			result.children.add(super.infer(obj.values.head));	
		}
		return result;			
	}
	
	override protected dispatch doInfer(ElementReferenceExpression obj, AbstractType type) {
		val arraySelectors = obj.arraySelector.map[it.ignoreCoercions];
		if(obj.arrayAccess && arraySelectors.head instanceof ValueRange) {
			val valRange = arraySelectors.head as ValueRange;
			
			val parentType = BaseUtils.getType(obj);
			val typeOfChildren = (parentType as TypeConstructorType).typeArguments.tail.head;
			
			val lowerBound = StaticValueInferrer.infer(valRange.lowerBound, [x |]);
			val upperBound = StaticValueInferrer.infer(valRange.upperBound, [x |]);
			if(!(lowerBound instanceof Integer && upperBound instanceof Integer)) {
				return new InvalidElementSizeInferenceResult(obj, parentType, "can not infer size for this range");
			}
			val elCount = (upperBound as Integer) - (lowerBound as Integer) + 1;
			
			val result = new ValidElementSizeInferenceResult(obj, parentType, elCount);
			result.children.add(obj.inferFromType(typeOfChildren));
			return result;
		} else {
			return super._doInfer(obj, type);
		}
	}
	
}