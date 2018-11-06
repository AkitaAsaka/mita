package org.eclipse.mita.base.typesystem.infra

import javax.inject.Inject
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.impl.BasicEObjectImpl
import org.eclipse.mita.base.scoping.BaseResourceDescriptionStrategy
import org.eclipse.mita.base.types.GeneratedObject
import org.eclipse.mita.base.typesystem.serialization.SerializationAdapter
import org.eclipse.mita.base.typesystem.solver.ConstraintSystem
import org.eclipse.mita.base.typesystem.solver.IConstraintSolver
import org.eclipse.mita.base.util.BaseUtils
import org.eclipse.xtext.diagnostics.IDiagnosticConsumer
import org.eclipse.xtext.diagnostics.IDiagnosticProducer
import org.eclipse.xtext.linking.impl.Linker
import org.eclipse.xtext.mwe.ResourceDescriptionsProvider
import org.eclipse.xtext.resource.IContainer
import org.eclipse.xtext.scoping.IScopeProvider

import static extension org.eclipse.mita.base.util.BaseUtils.force

class MitaLinker extends Linker {

	@Inject
	protected IConstraintSolver constraintSolver;
	
	@Inject
	protected IContainer.Manager containerManager;
	
	@Inject
	protected ResourceDescriptionsProvider resourceDescriptionsProvider;
	
	@Inject
	protected SerializationAdapter constraintSerializationAdapter;
	
	@Inject
	protected IScopeProvider scopeProvider;
	
	@Inject 
	protected MitaTypeLinker typeLinker;

	override linkModel(EObject model, IDiagnosticConsumer diagnosticsConsumer) {
		typeLinker.linkModel(model, diagnosticsConsumer)
		super.linkModel(model, diagnosticsConsumer)
	}

	override ensureLinked(EObject obj, IDiagnosticProducer producer) {
		if(obj.eContainer === null) {
			BaseUtils.ignoreChange(obj,  [
				obj.eAllContents.filter(GeneratedObject).forEach[it.generateMembers()]
			]);
			collectAndSolveTypes(obj, producer);
		}
		
		//super.ensureLinked(obj, producer)
	}
	
	def collectAndSolveTypes(EObject obj, IDiagnosticProducer producer) {
		// top level element - gather constraints and solve
		val resource = obj.eResource;
		val resourceDescriptions = resourceDescriptionsProvider.get(resource.resourceSet);
		val thisResourceDescription = resourceDescriptions.getResourceDescription(resource.URI);
		val thisExportedObjects = thisResourceDescription.exportedObjects;
		val visibleContainers = containerManager.getVisibleContainers(thisResourceDescription, resourceDescriptions);
		
		val exportedObjects = thisExportedObjects + (visibleContainers
			.flatMap[ it.exportedObjects ].force);
		val allConstraintSystems = exportedObjects
			.map[ it.getUserData(BaseResourceDescriptionStrategy.CONSTRAINTS) ]
			.filterNull
			.map[ constraintSerializationAdapter.deserializeConstraintSystemFromJSON(it, [ resource.resourceSet.getEObject(it, true) ]) ]
			.indexed.map[it.value.modifyNames('''.«it.key»''')].force;
		val combinedSystem = ConstraintSystem.combine(allConstraintSystems);
		
		if(combinedSystem !== null) {
			val preparedSystem = combinedSystem.replaceProxies(resource, scopeProvider);
			
			val solution = constraintSolver.solve(preparedSystem, obj);
			if(solution !== null) {
				if(resource instanceof MitaBaseResource) {
					resource.latestSolution = solution;
				}
			}
			if(solution !== null && solution.solution !== null) {
				solution.solution.substitutions.entrySet.forEach[
					var origin = it.key.origin;
					if(origin !== null && origin.eIsProxy) {
						origin = resource.resourceSet.getEObject((origin as BasicEObjectImpl).eProxyURI, false);
					}
					
					if(origin !== null) {
						val type = it.value;
						// we had the object loaded anyways, so we can set the type
						TypeAdapter.set(origin, type);
						
//						if(type instanceof BottomType) {
//							producer.addDiagnostic( new DiagnosticMessage(type.message, Severity.ERROR, "bottomType"));
//						}
					}
				]				
			}
		}
	}

	override protected clearReferences(EObject obj) {
		return;
	}
	
}