module RBS
  module AST
    class DuplicationFilter
      def initialize(env)
        @alias_decls = env.alias_decls
        @constant_decls = env.constant_decls
        @global_decls = env.global_decls
        @definition_builder = DefinitionBuilder.new(env: env)
        @type_name_resolver = TypeNameResolver.from_env(env)
      end

      def filter(decls, context: [Namespace.root])
        decls.filter_map do |decl|
          case decl
          when Declarations::Alias
            decl unless @alias_decls.key?(decl.name.absolute!)
          when Declarations::Constant
            decl unless @constant_decls.key?(decl.name.absolute!)
          when Declarations::Global
            decl unless @global_decls.key?(decl.name)
          else
            filter_members(decl, context: context)
          end
        end
      end

      def filter_members(decl, context:)
        return nil if decl.members.empty?

        inner_decls = filter(decl.each_decl.to_a, context: context + [decl.name.to_namespace])

        type_name = decl.name.absolute!
        members = decl.each_member.reject {|member| member_exists?(type_name, member, context: context)}

        members += inner_decls
        return decl if members == decl.members
        return nil if members.empty?

        replace_members(decl, members)
      end

      def member_exists?(type_name, member, context:)
        case member
        when Members::MethodDefinition
          name_in_definition?(type_name, member, member.name)
        when Members::Include
          mod = @type_name_resolver.resolve(member.name.absolute!, context: context)
          definition = @definition_builder.build_instance(type_name)
          definition.ancestors.ancestors.map(&:name).include?(mod)
        when Members::Alias
          name_in_definition?(type_name, member, member.new_name)
        when Members::Extend
          mod = @type_name_resolver.resolve(member.name.absolute!, context: context)
          definition = @definition_builder.build_singleton(type_name)
          definition.ancestors.ancestors.map(&:name).include?(mod)
        when Members::AttrAccessor, Members::AttrReader, Members::AttrWriter
          definition = @definition_builder.build_instance(type_name)
          definition.methods.key?(member.name)
        when Members::InstanceVariable
          definition = @definition_builder.build_instance(type_name)
          definition.instance_variables.key?(member.name)
        when Members::Public, Members::Private
          true
        end
      end

      def parse_type_name(string)
        Namespace.parse(string).yield_self do |namespace|
          last = namespace.path.last
          TypeName.new(name: last, namespace: namespace.parent)
        end.absolute!
      end

      def replace_members(decl, members)
        case decl
        when Declarations::Class
          decl.class.new(name: decl.name, type_params: decl.type_params, super_class: decl.super_class,
                         annotations: decl.annotations, location: decl.location, comment: decl.comment,
                         members: members)
        when Declarations::Module
          decl.class.new(name: decl.name, type_params: decl.type_params, self_types: decl.self_types,
                         annotations: decl.annotations, location: decl.location, comment: decl.comment,
                         members: members)
        when Declarations::Interface
          decl.class.new(name: decl.name, type_params: decl.type_params,
                         annotations: decl.annotations, location: decl.location, comment: decl.comment,
                         members: members)
        end
      end

      def name_in_definition?(type_name, member, name)
        definition =
          if type_name.interface?
            @definition_builder.build_interface(type_name)
          elsif member.singleton?
            @definition_builder.build_singleton(type_name)
          else
            @definition_builder.build_instance(type_name)
          end
        definition.methods.key?(name)
      end
    end
  end
end
