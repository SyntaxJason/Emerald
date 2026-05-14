require "../frontend/ast"
require "../semantic/resolver"
require "./interpreter"

module Emerald
  module MacroEngine
    class MacroExpander
      @interpreter : Interpreter

      def initialize
        @interpreter = Interpreter.new
      end

      def expand(program : AST::Program, resolver : Resolver)
        registry = program.macro_registry

        program.declarations.each do |decl|
          case decl
          when AST::ClassDecl
            expand_class(decl, registry, resolver)
          end
        end
      end

      private def expand_class(class_decl : AST::ClassDecl, registry : AST::MacroRegistry, resolver : Resolver)
        seen_annotations = {} of String => AST::Annotation

        class_decl.annotations.each do |ann|
          validate_annotation_not_duplicate!(ann, seen_annotations, "Class")

          macro_def = registry.find(ann.name)

          unless macro_def
            validate_annotation_known!(ann)
            next
          end

          unless macro_def.target == "Class"
            raise ResolveError.new(
              "Macro '@#{ann.name}' targets #{macro_def.target} but was applied to Class",
              ann.line,
              ann.col)
          end

          validate_annotation_not_duplicate!(ann, seen_annotations, "Class")

          @interpreter.run(macro_def.body, class_decl, "Class", ann.args)
        end

        class_decl.methods.each do |method|
          expand_method(method, class_decl, registry, resolver)
        end
      end


      private def validate_annotation_known!(ann : AST::Annotation)
        return if BUILTIN_ANNOTATION_NAMES.includes?(ann.name)

        raise ResolveError.new(
          "Unknown annotation '@#{ann.name}'. Define macro #{ann.name} or remove the annotation",
          ann.line,
          ann.col)
      end

      private def validate_annotation_not_duplicate!(ann : AST::Annotation, seen : Hash(String, AST::Annotation), target : String)
        if existing = seen[ann.name]?
          return if same_annotation_application?(existing, ann)

          raise ResolveError.new(
            "Duplicate annotation '@#{ann.name}' on same #{target} target",
            ann.line,
            ann.col)
        end

        seen[ann.name] = ann
      end

      private def same_annotation_application?(left : AST::Annotation, right : AST::Annotation) : Bool
        left.name == right.name &&
          left.line == right.line &&
          left.col == right.col
      end

      BUILTIN_ANNOTATION_NAMES = ["Override", "override", "Async", "Synchronized", "Deprecated"]

      private def expand_method(method : AST::MethodDecl, class_decl : AST::ClassDecl, registry : AST::MacroRegistry, resolver : Resolver)
        seen_annotations = {} of String => AST::Annotation

        method.annotations.each do |ann|
          validate_annotation_not_duplicate!(ann, seen_annotations, "Method")

          macro_def = registry.find(ann.name)

          unless macro_def
            validate_annotation_known!(ann)
            next
          end

          unless macro_def.target == "Method"
            raise ResolveError.new(
              "Macro '@#{ann.name}' targets #{macro_def.target} but was applied to Method",
              ann.line,
              ann.col)
          end

          @interpreter.run(macro_def.body, method, "Method", ann.args)
        end
      end
    end
  end
end
