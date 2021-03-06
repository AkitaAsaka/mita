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
import org.eclipse.emf.ecore.EObject
import org.eclipse.mita.base.expressions.ArrayAccessExpression
import org.eclipse.mita.base.expressions.AssignmentOperator
import org.eclipse.mita.base.expressions.ElementReferenceExpression
import org.eclipse.mita.base.expressions.PrimitiveValueExpression
import org.eclipse.mita.base.expressions.ValueRange
import org.eclipse.mita.base.expressions.util.ExpressionUtils
import org.eclipse.mita.base.types.CoercionExpression
import org.eclipse.mita.base.types.NamedElement
import org.eclipse.mita.base.types.Operation
import org.eclipse.mita.base.typesystem.types.AbstractType
import org.eclipse.mita.base.typesystem.types.TypeConstructorType
import org.eclipse.mita.program.ArrayLiteral
import org.eclipse.mita.program.EventHandlerDeclaration
import org.eclipse.mita.program.FunctionDefinition
import org.eclipse.mita.program.NewInstanceExpression
import org.eclipse.mita.program.ReturnStatement
import org.eclipse.mita.program.VariableDeclaration
import org.eclipse.mita.program.generator.AbstractFunctionGenerator
import org.eclipse.mita.program.generator.AbstractTypeGenerator
import org.eclipse.mita.program.generator.CodeFragment
import org.eclipse.mita.program.generator.CodeFragmentProvider
import org.eclipse.mita.program.generator.GeneratorUtils
import org.eclipse.mita.program.generator.StatementGenerator
import org.eclipse.mita.program.generator.TypeGenerator
import org.eclipse.mita.program.inferrer.ElementSizeInferrer
import org.eclipse.mita.program.inferrer.StaticValueInferrer
import org.eclipse.mita.program.inferrer.ValidElementSizeInferenceResult
import org.eclipse.xtext.EcoreUtil2
import org.eclipse.xtext.generator.trace.node.IGeneratorNode
import static extension org.eclipse.mita.base.types.TypesUtil.ignoreCoercions

class ArrayGenerator extends AbstractTypeGenerator {
	
	@Inject
	protected CodeFragmentProvider codeFragmentProvider
	
	@Inject
	protected extension GeneratorUtils generatorUtils
	
	@Inject
	protected ElementSizeInferrer sizeInferrer
	
	@Inject 
	protected extension StatementGenerator statementGenerator
	
	@Inject
	protected TypeGenerator typeGenerator
		
		
	private static def long getArraySize(VariableDeclaration stmt, ElementSizeInferrer sizeInferrer) {
		val inference = sizeInferrer.infer(stmt);
		return if(inference instanceof ValidElementSizeInferenceResult) {
			inference.elementCount;
		} else {
			return -1;
		}
	}
	private static def long getArraySize(NewInstanceExpression stmt, ElementSizeInferrer sizeInferrer) {
		val inference = sizeInferrer.infer(stmt);
		return if(inference instanceof ValidElementSizeInferenceResult) {
			inference.elementCount;
		} else {
			return -1;
		}
	}
	
	override CodeFragment generateHeader(EObject context, AbstractType type) {
		codeFragmentProvider.create('''
		typedef struct {
			«typeGenerator.code(context, (type as TypeConstructorType).typeArguments.tail.head)»* data;
			uint32_t length;
		} «typeGenerator.code(context, type)»;
		''').addHeader('MitaGeneratedTypes.h', false);
	}
	
	protected def boolean getIsOperationCall(EObject object) {
		if(object instanceof ElementReferenceExpression) {
			return object.isOperationCall && object.reference instanceof Operation;
		}
		return false;
	}
	
	override CodeFragment generateVariableDeclaration(AbstractType type, VariableDeclaration stmt) {
		val init = stmt.initialization.ignoreCoercions;
		val size = stmt.getArraySize(sizeInferrer);
		// if we are top-level, we must do initialization if there is any
		val topLevel = (EcoreUtil2.getContainerOfType(stmt, FunctionDefinition) === null) && (EcoreUtil2.getContainerOfType(stmt, EventHandlerDeclaration) === null);
		val occurrence = getOccurrence(stmt);
		val initWithValueLiteral = init !== null 
			&& init instanceof PrimitiveValueExpression 
			&& (init as PrimitiveValueExpression).value instanceof ArrayLiteral
		
		
		val operationCallInit = (!topLevel) && init !== null 
			&& init.isOperationCall;
		
		val otherInit = init !== null 
			&& !initWithValueLiteral
			&& !operationCallInit
		
		val cf = codeFragmentProvider.create('''
		«IF size > 0»
		// buffer for «stmt.name»
		«typeGenerator.code(stmt, (type as TypeConstructorType).typeArguments.tail.head)» data_«stmt.name»_«occurrence»[«size»]«IF initWithValueLiteral» = «statementGenerator.code(init)»«ENDIF»;
		«ELSE»
		// WARNING: Couldn't infer size!
		«ENDIF»
		// var «stmt.name»: array<«typeGenerator.code(stmt, (type as TypeConstructorType).typeArguments.tail.head)»>
		«typeGenerator.code(stmt, type)» «stmt.name»«IF topLevel || init !== null» = {
			.data = data_«stmt.name»_«occurrence»,
			.length = «size»
		}«ENDIF»;
		«IF !topLevel && otherInit»
		«generateExpression(type, stmt, AssignmentOperator.ASSIGN, init)»
		«ENDIF»
		''').addHeader('MitaGeneratedTypes.h', false);
		return cf;
	}
	
	override generateTypeSpecifier(AbstractType type, EObject context) {
		codeFragmentProvider.create('''array_«typeGenerator.code(context, (type as TypeConstructorType).typeArguments.tail.head)»''').addHeader('MitaGeneratedTypes.h', false);
	}
	
	override generateNewInstance(AbstractType type, NewInstanceExpression expr) {
		// if we are not in a function we are top-level and must do nothing, since we can't modify top-level anyway
		if(EcoreUtil2.getContainerOfType(expr, FunctionDefinition) === null && EcoreUtil2.getContainerOfType(expr, EventHandlerDeclaration) === null) {
			return CodeFragment.EMPTY;
		}
		
		val size = expr.getArraySize(sizeInferrer);
		val parent = expr.eContainer;
		val occurrence = getOccurrence(parent);
		val varName = generatorUtils.getBaseName(parent);
		
		// variable declarations create the buffer already
		val generateBuffer = (EcoreUtil2.getContainerOfType(expr, VariableDeclaration) === null);
		codeFragmentProvider.create('''
		«IF generateBuffer»
		«typeGenerator.code(expr, (type as TypeConstructorType).typeArguments.tail.head)» data_«varName»_«occurrence»[«size»];
		«ENDIF»
		// «varName» = new array<«typeGenerator.code(expr, type)»>(size = «size»);
		«varName» = («typeGenerator.code(expr, type)») {
			.data = data_«varName»_«occurrence»,
			.length = «size»
		};
		''').addHeader('MitaGeneratedTypes.h', false);
	}
	

	override generateExpression(AbstractType type, EObject left, AssignmentOperator operator, EObject _right) {
		val right = _right.ignoreCoercions;
		if(right === null) {
			return codeFragmentProvider.create('''''');
		}

		val isReturnStmt = left instanceof ReturnStatement;
		
		val varNameLeft = if(left instanceof VariableDeclaration) {
			// actually reference the thing, recursion would not terminate, since we get called if left is VariableDeclaration
			codeFragmentProvider.create('''«left.name»''');
		} 
		else if(isReturnStmt) {
			codeFragmentProvider.create('''(*_result)''');
		}
		else {
			// recurse
			codeFragmentProvider.create('''«statementGenerator.code(left).noTerminator»''');
		}
		val rightRef = if(right instanceof ArrayAccessExpression) {
			right.owner
		} else if(isReturnStmt) {
			(left as ReturnStatement).value
		} else {
			right
		}
		
		val isNewInstance = right instanceof NewInstanceExpression;
		
		val codeRightExpr = codeFragmentProvider.create('''«statementGenerator.code(rightRef).noTerminator»''');
		val rightExprIsValueLit = right instanceof PrimitiveValueExpression;
		val rightValueLit = if(right instanceof PrimitiveValueExpression) {
			right.value as ArrayLiteral;
		} else {
			null;
		}
		
		val valRange = if(right instanceof ArrayAccessExpression) {
			if(right.arraySelector instanceof ValueRange) {
				right.arraySelector as ValueRange;	
			}
		}
		
		val lengthLeft = codeFragmentProvider.create('''«varNameLeft».length''')
		val lengthRight = codeFragmentProvider.create('''«IF rightExprIsValueLit»«rightValueLit.values.length»«ELSE»«codeRightExpr».length«ENDIF»''');
		
		val valueType = (type as TypeConstructorType).typeArguments.tail.head;
		val dataLeft = codeFragmentProvider.create('''«varNameLeft».data''');
		val dataRight = codeFragmentProvider.create(
		'''«codeRightExpr».data«IF valRange !== null»«IF valRange.lowerBound !== null» + «valRange.lowerBound.code.noTerminator» * sizeof(«typeGenerator.code(left ?: right, valueType).noTerminator»)«ENDIF»«ENDIF»'''
		);
		
		
		val sizeResLeft = sizeInferrer.infer(left);
		val sizeResRight = sizeInferrer.infer(right);
		
		// if we can infer the sizes, we might be able to know that we don't need a new buffer to copy the data
		var long newElementCount = -1;
		var long oldElementCount = -1;
		val staticSize = sizeResLeft.valid && sizeResRight.valid;
		if(staticSize) {
			oldElementCount = (sizeResLeft as ValidElementSizeInferenceResult).elementCount;
			newElementCount = (sizeResRight as ValidElementSizeInferenceResult).elementCount;
		}
		
		val modifyLength = !staticSize || newElementCount != oldElementCount || isReturnStmt
		val modifyLengthReason = if(!staticSize) {
			"Could not infer size of one of the operands"
		} else if (newElementCount != oldElementCount) {
			"Array sizes are different"
		} else {
			"For safety we assign length of return variable"
		}
		
		
		val staticAccessors = new Object(){
			var field = true;
		};
		// if we can't infer one bound, we set staticAccessors.field to false
		// if x === null, the bound was null, which is valid
		// need object holding boolean, since in lambdas ref'ed vars must be final (== val)
		if(valRange !== null) {
			StaticValueInferrer.infer(valRange.lowerBound, [x| if(x !== null) staticAccessors.field = false])
			StaticValueInferrer.infer(valRange.upperBound, [x| if(x !== null) staticAccessors.field = false])
		}
		 
		// we might need to allocate a new buffer on the stack
		// PrimitiveValueExpression: target expr is an array literal
		// staticSize => oldBytec < newBytec: need more space
		val createNewBuffer = 
		       (rightExprIsValueLit) 
			|| !staticSize 
			|| (oldElementCount < newElementCount);
		val createNewBufferReason = if(rightExprIsValueLit) {
			"Need to store the array literal"
		} else if(!staticSize) {
			"Could not infer size of one of the operands or one of the operands is uninitialized"
		} else if(oldElementCount < newElementCount) {
			"Left array is too small"
		}
		
		val reallocBufferName = codeFragmentProvider.create('''dataRealloc_«left.uniqueIdentifier»''');
		
		val lengthModifyStmt = codeFragmentProvider.create('''«lengthLeft» = «lengthRight»«IF valRange !== null»«IF valRange.lowerBound !== null» - «valRange.lowerBound.code.noTerminator»«ENDIF»«IF valRange.upperBound !== null» - («lengthRight» - «valRange.upperBound.code.noTerminator»)«ENDIF»«ENDIF»''');
		val newLengthExpr = codeFragmentProvider.create('''«IF rightExprIsValueLit»«rightValueLit.values.length»«ELSE»«varNameLeft».length«ENDIF»''');
		
		val newBufferStmt = codeFragmentProvider.create('''«typeGenerator.code(left ?: right, valueType)» «reallocBufferName»[«newLengthExpr»]«IF rightExprIsValueLit» = «codeRightExpr»«ENDIF»''');
		
		val returnStatementLengthCheck = if(isReturnStmt) {
			codeFragmentProvider.create('''
			// We need enough space in our target array
			if(«lengthRight» < «lengthLeft») {
				«generateExceptionHandler(left, "EXCEPTION_INVALIDRANGEEXCEPTION")»
			}
			''')
		} else {
			CodeFragment.EMPTY;
		}
		
		val typeSize = codeFragmentProvider.create('''sizeof(«typeGenerator.code(left ?: right, valueType)»)''')
		
		codeFragmentProvider.create('''
		«returnStatementLengthCheck»
		«IF modifyLength»
		// Need to modify length: «modifyLengthReason»
		«lengthModifyStmt»;
		«ENDIF»
		«IF createNewBuffer»
		// Need to create new buffer: «createNewBufferReason»
		«newBufferStmt»;
		««« we mustn't assign the new buffer
		«IF !isReturnStmt»
		«dataLeft» = «reallocBufferName»;
		«ENDIF»
		«ENDIF»
		«IF !isNewInstance && !rightExprIsValueLit»
		// «varNameLeft» = «codeRightExpr»
		memcpy(«dataLeft», «dataRight», «typeSize» * «newLengthExpr»);
		««« we had to create a new buffer, but we mustn't pass it out
		«ELSEIF isReturnStmt && createNewBuffer»
		memcpy(«dataLeft», «reallocBufferName», «typeSize» * «newLengthExpr»);
		«ENDIF»
		''').addHeader('MitaGeneratedTypes.h', false);
	}
	
	static class LengthGenerator extends AbstractFunctionGenerator {
		
		@Inject
		protected CodeFragmentProvider codeFragmentProvider
		
		@Inject
		protected ElementSizeInferrer sizeInferrer
	

		override generate(ElementReferenceExpression ref, IGeneratorNode resultVariableName) {
			val variable = ExpressionUtils.getArgumentValue(ref.reference as Operation, ref, 'self');
			val varref = if(variable instanceof ElementReferenceExpression) {
				val varref = variable.reference;
				if(varref instanceof NamedElement) {
					varref.name
				}
			}
			
			return codeFragmentProvider.create('''«IF resultVariableName !== null»«resultVariableName» = «ENDIF»«varref».length''').addHeader('MitaGeneratedTypes.h', false);
		}
		
		override callShouldBeUnraveled(ElementReferenceExpression expression) {
			false
		}
		
	}
	
	override generateCoercion(CoercionExpression expr, AbstractType from, AbstractType to) {
		val inner = expr.value;
		if(inner instanceof ArrayLiteral) {
			return codeFragmentProvider.create('''«inner.code»''');
		}
		return codeFragmentProvider.create('''CANT COERCE «inner.eClass.name»''');
	}
	
}