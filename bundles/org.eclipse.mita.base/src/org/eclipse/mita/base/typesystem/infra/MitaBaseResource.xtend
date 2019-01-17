package org.eclipse.mita.base.typesystem.infra

import com.google.inject.Inject
import com.google.inject.name.Named
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EReference
import org.eclipse.emf.ecore.impl.BasicEObjectImpl
import org.eclipse.emf.ecore.impl.EObjectImpl
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.emf.ecore.resource.impl.ResourceImpl
import org.eclipse.mita.base.scoping.BaseResourceDescriptionStrategy
import org.eclipse.mita.base.types.GeneratedObject
import org.eclipse.mita.base.typesystem.serialization.SerializationAdapter
import org.eclipse.mita.base.typesystem.solver.ConstraintSolution
import org.eclipse.mita.base.typesystem.solver.ConstraintSystem
import org.eclipse.mita.base.typesystem.solver.IConstraintSolver
import org.eclipse.mita.base.typesystem.types.BottomType
import org.eclipse.mita.base.util.GZipper
import org.eclipse.xtend.lib.annotations.Accessors
import org.eclipse.xtext.diagnostics.Severity
import org.eclipse.xtext.linking.lazy.LazyLinkingResource
import org.eclipse.xtext.mwe.ResourceDescriptionsProvider
import org.eclipse.xtext.nodemodel.INode
import org.eclipse.xtext.resource.IContainer
import org.eclipse.xtext.resource.IFragmentProvider
import org.eclipse.xtext.resource.impl.ListBasedDiagnosticConsumer
import org.eclipse.xtext.scoping.IScopeProvider
import org.eclipse.xtext.util.CancelIndicator
import org.eclipse.xtext.util.Triple
import org.eclipse.xtext.validation.EObjectDiagnosticImpl
import org.eclipse.xtext.xtext.XtextFragmentProvider

import static extension org.eclipse.mita.base.util.BaseUtils.force
import org.eclipse.mita.base.util.BaseUtils
import java.io.InputStream
import java.util.Map
import java.io.IOException
import org.eclipse.mita.base.types.validation.IValidationIssueAcceptor.ValidationIssue

//class MitaBaseResource extends XtextResource {
class MitaBaseResource extends LazyLinkingResource {
	@Accessors
	protected ConstraintSolution latestSolution;
	@Accessors	
	protected MitaCancelInidicator cancelIndicator;
	
	
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
	
	@Inject @Named("typeLinker")
	protected MitaTypeLinker typeLinker;
	
	@Inject @Named("typeDependentLinker")
	protected MitaTypeLinker typeDependentLinker;
	
	@Inject
	protected XtextFragmentProvider fragmentProvider;

	override protected doLoad(InputStream inputStream, Map<?, ?> options) throws IOException {
		super.doLoad(inputStream, options)
	
		BaseUtils.ignoreChange(this, [|
			contents.get(0).eAllContents
				.filter(GeneratedObject)
				.forEach[
					it.generateMembers()
				]
			return;
		])
	}

	protected IFragmentProvider.Fallback fragmentProviderFallback = new IFragmentProvider.Fallback() {
		
		public override getFragment(EObject obj) {
			return MitaBaseResource.super.getURIFragment(obj);
		}
		
		public override getEObject(String fragment) {
			return MitaBaseResource.super.getEObject(fragment);
		}
	};

	new() {
		super();
		mkCancelIndicator();
	}
	
	override protected getEObject(String uriFragment, Triple<EObject, EReference, INode> triple) throws AssertionError {
		var model = triple.first;
		while (model.eContainer !== null) {
			model = model.eContainer;
		}

		val diagnosticsConsumer = new ListBasedDiagnosticConsumer();
		model.eAllContents
			.filter(GeneratedObject)
			.forEach[
				it.generateMembers()
			]
		typeLinker.doActuallyClearReferences(model);
		typeLinker.linkModel(model, diagnosticsConsumer);
		typeDependentLinker.linkModel(model, diagnosticsConsumer);
		collectAndSolveTypes(model);

		super.getEObject(uriFragment, triple)
	}
	
	def MitaCancelInidicator mkCancelIndicator() {
		cancelIndicator = new MitaCancelInidicator();
		return cancelIndicator;
	}
	
	static class MitaCancelInidicator implements CancelIndicator {
		public boolean canceled = false;
		override isCanceled() {
			return canceled;
		}
	}
	
	
	protected def resolveProxy(Resource resource, EObject obj) {
		(if(obj !== null && obj.eIsProxy) {
			if(obj instanceof EObjectImpl) {
				val uri = obj.eProxyURI;
				resource.resourceSet.getEObject(uri, true);
			}
		}) ?: obj;
	}
	
	def collectAndSolveTypes(EObject obj) {
		// top level element - gather constraints and solve
		val resource = obj.eResource;
		val errors = if(resource instanceof ResourceImpl) {
			resource.errors;
		}
		if(!errors.nullOrEmpty) {
			return;
		}
		
		val resourceDescriptions = resourceDescriptionsProvider.get(resource.resourceSet);
		val thisResourceDescription = resourceDescriptions.getResourceDescription(resource.URI);
		val visibleContainers = containerManager.getVisibleContainers(thisResourceDescription, resourceDescriptions);
		
		val cancelIndicator = if(resource instanceof MitaBaseResource) {
			resource.mkCancelIndicator();
		}
		
		val exportedObjects = /*thisExportedObjects + */(visibleContainers
			.flatMap[ it.exportedObjects ].force);
		val jsons = exportedObjects
			.map[ it.EObjectURI -> it.getUserData(BaseResourceDescriptionStrategy.CONSTRAINTS) ]
			.filter[it.value !== null]
			.map[it.value]
			.map[GZipper.decompress(it)].force;
		if(obj.eResource.URI.lastSegment == "application.mita") {
			print("")
		}
		val allConstraintSystems = jsons
			.map[ constraintSerializationAdapter.deserializeConstraintSystemFromJSON(it, [ 
				return resource.resourceSet.getEObject(it, true);
//				val resourceOfObj = resource.resourceSet.getResource(it.trimFragment, true);
//				return fragmentProvider.getEObject(resourceOfObj, it.fragment, fragmentProviderFallback);
			]) ]
			.indexed.map[it.value.modifyNames('''.«it.key»''')].force;
		
		if(cancelIndicator !== null && cancelIndicator.canceled) {
			return;
		}
		
		val combinedSystem = ConstraintSystem.combine(allConstraintSystems);
		
		if(combinedSystem !== null) {
			val preparedSystem = combinedSystem.replaceProxies(resource, scopeProvider);
			if(cancelIndicator !== null && cancelIndicator.canceled) {
				return;
			}
			
			val solution = constraintSolver.solve(preparedSystem, obj);
			if(solution !== null) {
				if(resource instanceof MitaBaseResource) {
					solution.solution.substitutions.entrySet.forEach[
						var origin = it.key.origin;
						if(origin !== null && origin.eIsProxy) {
							origin = resource.resourceSet.getEObject((origin as BasicEObjectImpl).eProxyURI, false);
						}
						
						if(origin !== null) {
							val type = it.value;
							// we had the object loaded anyways, so we can set the type
							TypeAdapter.set(origin, type);
							
							if(type instanceof BottomType) {
								solution.issues += new ValidationIssue(type.message, resolveProxy(resource, type.origin) ?: obj)
							}
						}
					]
					resource.latestSolution = solution;
					resource.cancelIndicator.canceled = true;
					resource.errors += solution.issues.filter[it.target !== null].toSet.filter[it.severity == Severity.ERROR].map[
						new EObjectDiagnosticImpl(it.severity, it.issueCode, it.message, resolveProxy(resource, it.target) ?: obj, it.feature, 0, #[]);
					]
					resource.warnings += solution.issues.filter[it.target !== null].toSet.filter[it.severity == Severity.WARNING].map[
						new EObjectDiagnosticImpl(it.severity, it.issueCode, it.message, resolveProxy(resource, it.target) ?: obj, it.feature, 0, #[]);
					]
					resource.warnings += solution.issues.filter[it.target !== null].toSet.filter[it.severity == Severity.INFO].map[
						new EObjectDiagnosticImpl(it.severity, it.issueCode, it.message, resolveProxy(resource, it.target) ?: obj, it.feature, 0, #[]);
					]
				}
			}
		}
	}
	
}
