# Minitest 6 nie bundluje już minitest/mock (brak Object#stub) — minimalny
# zamiennik do podmiany metod singletonowych (np. Rails.env)
# na czas bloku, z gwarantowanym przywróceniem oryginału.
module StubHelpers
  def stub_singleton(object, method_name, replacement)
    original = object.method(method_name)
    object.singleton_class.silence_redefinition_of_method(method_name)
    object.define_singleton_method(method_name) do |*args, **kwargs, &blk|
      replacement.call(*args, **kwargs, &blk)
    end
    yield
  ensure
    object.singleton_class.silence_redefinition_of_method(method_name)
    object.define_singleton_method(method_name, original)
  end
end

ActiveSupport::TestCase.include StubHelpers
