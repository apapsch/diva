using Gee;

namespace Diva
{
    internal class AutoTypeRegistration<T> : Object, IRegistrationContext<T>
    {
        private Collection<ServiceRegistration> _services = new LinkedList<ServiceRegistration>();
        private Collection<Type> _decorations = new LinkedList<Type>();

        internal Collection<ServiceRegistration> services {get{return _services;}}
        internal Collection<Type> decorations {get{return _decorations;}}
        internal CreationStrategy creation_strategy {get; set;}

        private Collection<string> ignored_properties = new ArrayList<string>();

        public ICreator<T> get_creator()
        {
            return creation_strategy.get_final_creator<T>(new AutoTypeCreator<T>(this, ignored_properties));
        }

        public IRegistrationContext<T> ignore_property(string property)
        {
            ignored_properties.add(property);
            return this;
        }

        private class AutoTypeCreator<T> : Object, ICreator<T>
        {
            private AutoTypeRegistration<T> registration;
            private Collection<string> ignored_properties;

            public AutoTypeCreator(AutoTypeRegistration<T> registration, Collection<string> ignored_properties)
            {
                this.registration = registration;
                this.ignored_properties = ignored_properties;
            }

            public T create(ComponentContext context)
                throws ResolveError
            {
                return create_lazy(context).value;
            }

            public Lazy<T> create_lazy(ComponentContext context)
                throws ResolveError
            {
                var cls = typeof(T).class_ref();
                var properties = ((ObjectClass)cls).list_properties();
                var params = new HashMap<string, Lazy<Object>>();
                
                foreach(var prop in properties)
                {
                    if(ignored_properties.contains(prop.name))
                        continue;
                    if(can_inject_property(prop))
                    {
                        var p = Parameter();
                        var t = prop.value_type;
                        p.name = prop.name;
                        p.value = Value(t);

                        try
                        {
                            LazyCreatorFunc func;
                            if(is_special_lazy(t, out func))
                                params[prop.name] = func(prop, context);
                            else
                                params[prop.name] = context.resolve_lazy_typed(t);
                        }
                        catch(ResolveError e)
                        {
                            throw new ResolveError.InnerError(@"Cannot satify parameter $(prop.name) [$(t.name())]: $(e.message)");
                        }
                    }
                }
                return new Lazy<T>(() => 
                        { 
                            var props = ((ObjectClass)cls).list_properties();
                            var parameters = new Parameter[] {};
                            foreach(var prop in props)
                            {
                                if(ignored_properties.contains(prop.name))
                                    continue;
                                var p = Parameter();
                                var t = prop.value_type;
                                p.name = prop.name;
                                p.value = Value(t);
                                
                                if(t == typeof(Lazy))
                                {
                                    p.value.set_instance(params[prop.name].value);
                                }
                                else
                                {
                                    p.value.set_object(params[prop.name].value);
                                }
                                
                                parameters += p;
                            }
                            return (T) Object.newv(typeof(T), parameters);                            
                        });
            }

            private bool can_inject_property(ParamSpec p)
            {
                var flags = p.flags;
                return (  ((flags & ParamFlags.CONSTRUCT) == ParamFlags.CONSTRUCT)
                  || ((flags & ParamFlags.CONSTRUCT_ONLY) == ParamFlags.CONSTRUCT_ONLY));
            }

            private bool is_special_lazy(Type t, out LazyCreatorFunc func)
            {
                if(t == typeof(Lazy))
                {
                    func = lazy_lazy_creator;
                    return true;
                }
                if(t == typeof(Index))
                {
                    func = lazy_index_creator;
                    return true;
                }
                if(t == typeof(Collection))
                {
                    func = lazy_collection_creator;
                    return true;
                }
                func = null;
                return false;
            }

            private delegate Lazy<Object> LazyCreatorFunc(ParamSpec p, ComponentContext context)
                throws ResolveError;
            
            private Lazy lazy_lazy_creator(ParamSpec p, ComponentContext context)
                throws ResolveError
            {
                // get the type
                var lazy_data = (LazyPropertyData)p.get_qdata(LazyPropertyData.q);
                if(lazy_data == null)
                    throw new ResolveError.BadDeclaration("To support injection of lazy properties, call SetLazyInjection in your static construct block.");
                Type t = lazy_data.dep_type;
                
                var lazy = context.resolve_lazy_typed(t);

                return new Lazy<Lazy>(() => lazy);
            }

            private Lazy<Object> lazy_collection_creator(ParamSpec p, ComponentContext context)
                throws ResolveError
            {
                // get the type
                var collection_data = (CollectionPropertyData)p.get_qdata(CollectionPropertyData.q);
                if(collection_data == null)
                    throw new ResolveError.BadDeclaration("To support injection of collection properties, call SetCollectionInjection in your static construct block.");
                Type t = collection_data.dep_type;

                return new Lazy<Collection>(() => context.resolve_collection_typed(t));
            }

            private Lazy<Object> lazy_index_creator(ParamSpec p, ComponentContext context)
                throws ResolveError
            {
                var index_data = (IndexPropertyData)p.get_qdata(IndexPropertyData.q);
                if(index_data == null)
                     throw new ResolveError.BadDeclaration("To support injection of index properties, call SetIndexedInjection in your static construct block.");
                
                var index = context.resolve_index_typed(index_data.dependency, index_data.key);
                return new Lazy<Index>(() => index);
            }
        }
    }
}
