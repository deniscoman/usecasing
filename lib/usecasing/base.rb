module UseCase

  module BaseClassMethod

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def required_params(*params)
        @parameters ||= ((superclass.required_params.dup if superclass.respond_to?(:required_params)) || []).push(*params)
      end

      def depends(*deps)
        @dependencies ||= []
        @dependencies.push(*deps)
      end

      def dependencies
        return [] unless superclass.ancestors.include? UseCase::Base
        value = (@dependencies && @dependencies.dup || []).concat(superclass.dependencies)
        value
      end

      def perform(ctx = { })
        tx(ExecutionOrder.run(self), ctx) do |usecase, context|
          instance = usecase.new(context)
          instance.tap do | me |
            me.required_params
            me.before
            me.perform
          end
        end
      end

      private

      def tx(execution_order, context)
        ctx = (context.is_a?(Context) ? context : Context.new(context))
        executed = []
        execution_order.each do |usecase|
          break if !ctx.success? || ctx.stopped?
          executed.push(usecase)
          yield usecase, ctx
        end
        rollback(executed, ctx) unless ctx.success?
        ctx
      end

      def rollback(execution_order, context)
        execution_order.each do |usecase|
          usecase.new(context).rollback
        end
        context
      end

    end #ClassMethods
  end #BaseClassMethod

  class Base

    include BaseClassMethod

    attr_reader :context
    def initialize(context)
      @context = context
    end

    def required_params
      self.class.required_params.each do |param|
        if context.to_hash.keys.include? param
          instance_variable_set("@#{param}", @context.send(param))
        else
          raise ArgumentError.new("#{param} is not a context parameter")
        end
      end
    end

    def before;  end
    def perform;  end
    def rollback; end

    def stop!
      context.stop!
    end

    def failure(key, value)
      @context.failure(key, value)
    end
  end
end