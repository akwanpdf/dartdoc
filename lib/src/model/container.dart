// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/scope.dart';
import 'package:dartdoc/src/model/comment_referable.dart';
import 'package:dartdoc/src/model/model.dart';
import 'package:dartdoc/src/model_utils.dart' as model_utils;
import 'package:dartdoc/src/quiver.dart' as quiver;
import 'package:meta/meta.dart';

/// A [Container] represents a Dart construct that can contain methods,
/// operators, and fields, such as [Class], [Enum], or [Extension].
///
/// Member naming in [Container] follows these general rules:
///
/// **instance** : Members named 'instance' contain the children of this
/// container that can be referenced from within the container without a prefix.
/// Usually overridden in subclasses with calls to super.
/// **constant** : Members named 'constant' contain children declared constant.
/// **variable** : The opposite of constant.  For the templating system.
/// **static** : Members named 'static' are related to static children of this
/// container.
/// **public** : Filtered versions of the getters showing only public items.
/// Mostly for the templating system.
/// **sorted** : Filtered versions of the getters creating a sorted list by
/// name.  For the templating system.
/// **has** : boolean getters indicating whether the underlying getters are
/// empty.  Mostly for the templating system.
/// **all** : Referring to all children.
abstract class Container extends ModelElement with TypeParameters {
  Container(Element element, Library library, PackageGraph packageGraph)
      : super(element, library, packageGraph);

  // TODO(jcollins-g): Implement a ContainerScope that flattens supertypes?
  @override
  Scope get scope => null;

  @override
  bool get hasParameters => false;

  /// Is this a class (but not an enum)?
  bool get isClass =>
      element is ClassElement && !(element as ClassElement).isEnum;
  bool get isExtension => element is ExtensionElement;

  /// For templates, classes and extensions have much in common despite
  /// differing underlying implementations in the analyzer.
  bool get isClassOrExtension => isClass || isExtension;
  bool get isEnum =>
      element is ClassElement && (element as ClassElement).isEnum;
  bool get isClassOrEnum => isClass || isEnum;
  bool get isMixin =>
      element is ClassElement && (element as ClassElement).isMixin;

  @mustCallSuper
  Iterable<ModelElement> get allModelElements => quiver.concat([
        instanceMethods,
        instanceFields,
        instanceOperators,
        instanceAccessors,
        staticFields,
        staticAccessors,
        staticMethods,
      ]);

  /// All methods, including operators and statics, declared as part of this
  /// [Container].  [declaredMethods] must be the union of [instanceMethods],
  /// [staticMethods], and [instanceOperators].
  Iterable<Method> get declaredMethods;

  Iterable<Method> get instanceMethods => declaredMethods
      .where((m) => !m.isStatic && !m.isOperator)
      .toList(growable: false);

  /// Whether all instance fields are inherited.
  bool get publicInheritedInstanceFields => false;

  /// Whether all instance methods are inherited.
  bool get publicInheritedInstanceMethods => false;

  /// Whether all instance operators are inherited.
  bool get publicInheritedInstanceOperators => false;

  bool get hasPublicConstructors;

  Iterable<Constructor> get publicConstructorsSorted;

  @nonVirtual
  bool get hasPublicInstanceMethods =>
      model_utils.filterNonPublic(instanceMethods).isNotEmpty;

  Iterable<Method> get publicInstanceMethods =>
      model_utils.filterNonPublic(instanceMethods);

  List<Method> _publicInstanceMethodsSorted;
  List<Method> get publicInstanceMethodsSorted =>
      _publicInstanceMethodsSorted ?? publicInstanceMethods.toList()
        ..sort(byName);

  Iterable<Operator> _declaredOperators;
  @nonVirtual
  Iterable<Operator> get declaredOperators {
    _declaredOperators ??=
        declaredMethods.whereType<Operator>().toList(growable: false);
    return _declaredOperators;
  }

  @override
  ModelElement get enclosingElement;

  Iterable<Operator> get instanceOperators => declaredOperators;

  @nonVirtual
  bool get hasPublicInstanceOperators =>
      publicInstanceOperatorsSorted.isNotEmpty;

  @nonVirtual
  Iterable<Operator> get publicInstanceOperators =>
      model_utils.filterNonPublic(instanceOperators);

  List<Operator> _publicInstanceOperatorsSorted;
  List<Operator> get publicInstanceOperatorsSorted =>
      _publicInstanceOperatorsSorted ??= publicInstanceOperators.toList()
        ..sort(byName);

  /// Fields fully declared in this [Container].
  Iterable<Field> get declaredFields;

  /// All fields accessible in this instance that are not static.
  Iterable<Field> get instanceFields =>
      declaredFields.where((f) => !f.isStatic);

  bool get hasInstanceFields => instanceFields.isNotEmpty;

  @nonVirtual
  Iterable<Field> get publicInstanceFields =>
      model_utils.filterNonPublic(instanceFields);

  @nonVirtual
  bool get hasPublicInstanceFields => publicInstanceFields.isNotEmpty;

  List<Field> _publicInstanceFieldsSorted;
  List<Field> get publicInstanceFieldsSorted => _publicInstanceFieldsSorted ??=
      publicInstanceFields.toList()..sort(byName);

  Iterable<Field> get constantFields => declaredFields.where((f) => f.isConst);

  Iterable<Field> get publicConstantFields =>
      model_utils.filterNonPublic(constantFields);

  bool get hasPublicConstantFields => publicConstantFieldsSorted.isNotEmpty;

  List<Field> _publicConstantFieldsSorted;
  List<Field> get publicConstantFieldsSorted => _publicConstantFieldsSorted ??=
      publicConstantFields.toList()..sort(byName);

  Iterable<Accessor> get instanceAccessors =>
      instanceFields.expand((f) => f.allAccessors);

  Iterable<Accessor> get staticAccessors =>
      staticFields.expand((f) => f.allAccessors);

  /// This container might be canonical for elements it does not contain.
  /// See [Inheritable.canonicalEnclosingContainer].
  bool containsElement(Element element) => allElements.contains(element);

  Set<Element> _allElements;
  Set<Element> get allElements =>
      _allElements ??= allModelElements.map((e) => e.element).toSet();

  Map<String, List<ModelElement>> _membersByName;

  /// Given a ModelElement that is a member of some other class, return
  /// the member of this class that has the same name and runtime type.
  ///
  /// This enables object substitution for canonicalization, such as Interceptor
  /// for Object.
  T memberByExample<T extends ModelElement>(T example) {
    if (_membersByName == null) {
      _membersByName = {};
      for (var me in allModelElements) {
        if (!_membersByName.containsKey(me.name)) {
          _membersByName[me.name] = [];
        }
        _membersByName[me.name].add(me);
      }
    }
    ModelElement member;
    // [T] is insufficiently specific to disambiguate between different
    // subtypes of [Inheritable] or other mixins/implementations of
    // [ModelElement] via [Iterable.whereType].
    var possibleMembers = _membersByName[example.name]
        .where((e) => e.runtimeType == example.runtimeType);
    if (example is Accessor) {
      possibleMembers = possibleMembers
          .where((e) => example.isGetter == (e as Accessor).isGetter);
    }
    member = possibleMembers.first;
    assert(possibleMembers.length == 1);
    return member;
  }

  Map<String, List<ModelElement>> _allModelElementsByNamePart;

  /// Helper for `_MarkdownCommentReference._getResultsForClass`.
  Map<String, List<ModelElement>> get allModelElementsByNamePart {
    if (_allModelElementsByNamePart == null) {
      _allModelElementsByNamePart = {};
      for (var me in allModelElements) {
        _allModelElementsByNamePart.update(
            me.namePart, (List<ModelElement> v) => v..add(me),
            ifAbsent: () => <ModelElement>[me]);
      }
    }
    return _allModelElementsByNamePart;
  }

  bool get hasPublicStaticFields => publicStaticFieldsSorted.isNotEmpty;

  Iterable<Field> get publicStaticFields =>
      model_utils.filterNonPublic(staticFields);

  List<Field> _publicStaticFieldsSorted;
  List<Field> get publicStaticFieldsSorted =>
      _publicStaticFieldsSorted ??= publicStaticFields.toList()..sort(byName);

  Iterable<Field> get staticFields => declaredFields.where((f) => f.isStatic);

  Iterable<Field> get variableStaticFields =>
      staticFields.where((f) => !f.isConst);

  bool get hasPublicVariableStaticFields =>
      publicVariableStaticFieldsSorted.isNotEmpty;

  Iterable<Field> get publicVariableStaticFields =>
      model_utils.filterNonPublic(variableStaticFields);

  List<Field> _publicVariableStaticFieldsSorted;
  List<Field> get publicVariableStaticFieldsSorted =>
      _publicVariableStaticFieldsSorted ??= publicVariableStaticFields.toList()
        ..sort(byName);

  Iterable<Method> get staticMethods =>
      declaredMethods.where((m) => m.isStatic);

  bool get hasPublicStaticMethods =>
      model_utils.filterNonPublic(publicStaticMethodsSorted).isNotEmpty;

  Iterable<Method> get publicStaticMethods =>
      model_utils.filterNonPublic(staticMethods);

  List<Method> _publicStaticMethodsSorted;
  List<Method> get publicStaticMethodsSorted =>
      _publicStaticMethodsSorted ??= publicStaticMethods.toList()..sort(byName);

  Map<String, CommentReferable> _referenceChildren;
  @override
  @mustCallSuper
  Map<String, CommentReferable> get referenceChildren {
    if (_referenceChildren == null) {
      _referenceChildren = {};
      for (var modelElement in allModelElements) {
        // Never directly look up accessors.
        if (modelElement is Accessor) continue;
        if (modelElement is Constructor) {
          // Populate default constructor names so they make sense for the
          // new lookup code.
          var constructorName = modelElement.element.name;
          if (constructorName == '') {
            constructorName = name;
          }
          _referenceChildren[constructorName] = modelElement;
          continue;
        }
        if (modelElement is Operator) {
          // TODO(jcollins-g): once todo in [Operator.name] is fixed, remove
          // this special case.
          _referenceChildren[modelElement.element.name] = modelElement;
        } else {
          _referenceChildren[modelElement.name] = modelElement;
        }
      }
      // Process unscoped parameters last to make sure they don't override
      // other options.
      for (var modelElement in allModelElements) {
        // Don't complain about references to parameter names, but prefer
        // referring to anything else.
        // TODO(jcollins-g): Figure out something good to do in the ecosystem
        // here to wean people off the habit of unscoped parameter references.
        if (modelElement.hasParameters) {
          for (var parameterElement in modelElement.parameters) {
            _referenceChildren.putIfAbsent(
                parameterElement.name, () => parameterElement);
          }
        }
      }
      _referenceChildren['this'] = this;
    }
    return _referenceChildren;
  }

  @override
  Iterable<CommentReferable> get referenceParents => [enclosingElement];
}
