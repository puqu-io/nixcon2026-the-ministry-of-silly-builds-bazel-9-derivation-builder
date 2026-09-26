# This is fun

# Add stuff from bazel_features_globals here!
# TODO! Sic!
native = struct(
    bazel_version = "9.2.0",
    legacy_globals = struct(
        cc_proto_aspect = None,
        CcSharedLibraryInfo = None,
        CcSharedLibraryHintInfo = None,
        JavaInfo = None,
        JavaPluginInfo = None,
        macro = None,
        PackageSpecificationInfo = None,
        ProtoInfo = None,
        PyCcLinkParamsProvider = None,
        PyInfo = None,
        PyRuntimeInfo = None,
        RuntimeEnvironmentInfo = None,
        set = None,
        subrule = None,
        DefaultInfo = None,
        __TestingOnly_NeverAvailable = None,        
    )
)

# Sigh
def macro(**kwargs):
    panic("macro called")

def PackageSpecificationInfo(**kwargs):
    panic("PackageSpecificationInfo called")

def RunEnvironmentInfo(**kwargs):
    panic("RunEnvironmentInfo called")

def subrule(**kwargs):
    panic("subrule called") 

def DefaultInfo(**kwargs):
    panic("DefaultInfo called")

def OutputGroupInfo(**kwargs):
    panic("OutputGroupInfo called")

def provider_magic(*args,**kwargs):
    field_names = kwargs.get("fn", [])
    res = {}
    for i, field_name in enumerate(field_names):
        if i >= len(args):
            res[field_name] = None
        else:
            res[field_name] = args[i]

    return struct(**res)

def aspect(*args, **kwargs):
    return struct(*args, **kwargs)

def transition(*args, **kwargs):
    return struct(*args, **kwargs)

# Sick! Providers now
def provider(*pargs, **pkwargs):
    fields = pkwargs.get("fields", None)
    if str(type(fields)) == "list":
        field_names = fields
    elif str(type(fields)) == "dict":
        field_names = fields.keys()
    else:
        field_names = []

    if pkwargs.get("init", None):
        return (lambda *args, **kwargs: provider_magic(fn=field_names,*args), struct())
    return lambda *args, **kwargs: provider_magic(field_names=field_names,*args)

def depset(*args, **kwargs):
    # return struct(**kwargs)
    # TODO args?
    self = struct(
        _inner = set(),
        to_list = lambda: [x for x in self._inner]
    )
    for arg in args:
        if str(type(arg)) == "list":
            for a in arg:
                self._inner.add(a)
    for t in kwargs.get("transitive", []):
        self._inner.add(t)
    return self

def rule(**rule_kwargs):
    return lambda **kwargs: struct()


def attr_handling(kind, **kwargs):
    kwargs["__internal_kind"] = kind
    return kwargs

## KILL ME
def select(*args, **kwargs):
    pass

platform_common = struct(
    TemplateVariableInfo = lambda *args, **kwargs: "TEMPLATE",
)

# WHATi
_cc_common = struct(
    create_header_info = lambda: set(),
    freeze = lambda x: x,
    do_not_use_tools_cpp_compiler_present = True,
)
cc_common = struct(
    internal_DO_NOT_USE = lambda: _cc_common,
    create_header_info = lambda: set(),
    freeze = lambda x: x,
    do_not_use_tools_cpp_compiler_present = True,
)

config = struct(
    bool = lambda **kwargs: struct(),
    int = lambda **kwargs: struct(),
    string_list = lambda **kwargs: struct(),
    string = lambda **kwargs: struct(),
)

config_common = struct(
    toolchain_type = lambda *args, **kwargs: None,
)

coverage_common = struct(
    instrumented_files_info = lambda *args, **kwargs: struct(),
)

def configuration_field(*args, **kwargs):
    return struct(*args, **kwargs)

def visibility(*args, **kwargs):
    pass

# Kek
attr = struct(
    bool = lambda **kwargs: attr_handling("bool", **kwargs),
    int = lambda **kwargs: attr_handling("int", **kwargs),
    label = lambda **kwargs: attr_handling("string", **kwargs),
    label_list = lambda **kwargs: attr_handling("list", **kwargs),
    label_keyed_string_dict = lambda **kwargs: attr_handling("dict", **kwargs),
    string_dict = lambda **kwargs: attr_handling("dict", **kwargs),
    string_list_dict = lambda **kwargs: attr_handling("dict", **kwargs),
    string_list = lambda **kwargs: attr_handling("list", **kwargs),
    string = lambda **kwargs: attr_handling("string", **kwargs),
)

# This will require work
def Label(input):
    self = struct(
        _inner = input,
        repo_name = input,
    )
    return self

# Components of repository_ctx
def repository_ctx_download_and_extract(repository_name, *args, **kwargs):
    urls = kwargs.get("urls", [kwargs.get("url", "no url found")])
    sha256 = kwargs.get("sha256", kwargs.get("integrity", "no integrity found"))
    # print("repository_ctx.download_and_extract called with: url:{} sha256:{}".format(url, sha256))
    # TODO: download_and_extract might have urls and integrity and ...
    bazel_report_download(
        urls[0].rsplit("/", 1)[-1],
        sha256,
        "<kind-to-be-used>",
        " ".join(urls),
    )
    return

def gen_repository_ctx_download_and_extract(repository_name, *args, **kwargs):
    return lambda *args, **kwargs: repository_ctx_download_and_extract(repository_name, *args, **kwargs)

# Components of repository_ctx
def repository_ctx_download(repository_name, *args, **kwargs):
    urls = kwargs.get("urls", [kwargs.get("url", "no url found")])
    
    sha256 = kwargs.get("sha256", kwargs.get("integrity", "no integrity found"))
    # print("repository_ctx.download_and_extract called with: url:{} sha256:{}".format(url, sha256))
    # TODO: download_and_extract might have urls and integrity and ...
    bazel_report_download(
        urls[0].rsplit("/", 1)[-1],
        sha256,
        "<kind-to-be-used>",
        " ".join(urls),
    )
    return

def gen_repository_ctx_download(repository_name, *args, **kwargs):
    return lambda *args, **kwargs: repository_ctx_download(repository_name, *args, **kwargs)

def repository_ctx_file(repository_name, *args, **kwargs):
    path = args[0]
    content = kwargs.get("content", args[1])
    executable = kwargs.get("executable", True)
    legacy_utf8 = kwargs.get("legacy_utf8", False)

    return bazel_rctx_file(
        repository_name,
        path,
        content,
        executable,
        legacy_utf8
    )

def gen_repository_ctx_file(repository_name):
    return lambda *args, **kwargs: repository_ctx_file(repository_name, *args, **kwargs)

def repository_ctx_template(repository_name, *args, **kwargs):
    # TODO: render out?
    return

def gen_repository_ctx_template(repository_name):
    return lambda *args, **kwargs: repository_ctx_template(repository_name, *args, **kwargs)

def tag_class(**kwargs):
    return kwargs

def execute_module_extension_impl(
    impl,
    tag_class_name,
    tag_classes,
    **kwargs,
):  
    if not tag_class_name and not tag_classes:
        module_ctx = struct(
            # TODO
            extension_metadata = lambda **kwargs: kwargs,
            # https://bazel.build/rules/lib/builtins/bazel_module
            modules = [
                struct(
                    is_root = True,
                    name = "fake_root_module",
                    tags = struct(**{}),
                    version = "fake_root_module_version",
                ),
                struct(
                    is_root = False,
                    # Just great
                    name = "rules_rut",
                    tags = struct(**{}),
                    version = "fake_rules_rust_version",
                )
            ]
        )
        
        return impl(module_ctx)

    tags_as_dict = {}

    for class_name, class_meta in tag_classes.items():
        attrs_with_defaults = {}
        for attr_name, attr_metadata in class_meta.get("attrs", {}).items():
            attr_default_value_kind = attr_metadata.get(
                "__internal_kind",
                "UNABLE_TO_GET_INTERNAL_KIND"
            )
            if attr_default_value_kind == "string":
                attr_default_value = attr_metadata.get("default", "")
            elif attr_default_value_kind == "list":
                attr_default_value = attr_metadata.get("default", [])
            elif attr_default_value_kind == "dict":
                attr_default_value = attr_metadata.get("default", {})
            elif attr_default_value_kind == "bool":
                attr_default_value = attr_metadata.get("default", False)
            elif attr_default_value_kind == "int":
                attr_default_value = attr_metadata.get("default", 0)
            else:
                attr_default_value = attr_metadata.get("default", None)

            passed_in_attr_value = kwargs.get(attr_name, None)
            if not passed_in_attr_value:
                attr_value = attr_default_value
            else:
                attr_value = passed_in_attr_value

            attrs_with_defaults[attr_name] = attr_value

        tags_as_dict[class_name]=[struct(**attrs_with_defaults)]

    # TODO: This needs to be something more
    module_ctx = struct(
        # TODO
        extension_metadata = lambda **kwargs: kwargs,
        # https://bazel.build/rules/lib/builtins/bazel_module
        modules = [
            struct(
                is_root = True,
                name = "fake_root_module",
                tags = struct(**tags_as_dict),
                version = "fake_root_module_version",
            ),
            struct(
                is_root = False,
                name = "rules_rust",
                tags = struct(**tags_as_dict),
                version = "fake_rules_rust_version",
            )
        ]
    )
    return impl(module_ctx)

def module_extension(
    implementation = None,
    **module_extension_kwargs,
):
    if module_extension_kwargs.get("tag_classes", {}):
        # TODO: need to provide all classes and all tags
        # TODO: What would happen with two calls to the same tag class?
        return struct(**{
            tag_class_name: lambda **kwargs: execute_module_extension_impl(implementation, tag_class_name, module_extension_kwargs.get("tag_classes", {}), **kwargs)
            for tag_class_name in module_extension_kwargs.get("tag_classes", {}).keys()
        })
    else:
        return lambda **kwargs: execute_module_extension_impl(implementation, None, None, **kwargs)

def extension_metadata(
    # Both of those should be "all" if root module has nondev dependency wtf
    root_module_direct_deps = [],
    root_module_direct_dev_deps = [],
    **kwargs
):
    # TODO: Should actually return something
    return {}

########
def invoke_repository_rule_impl(impl, attrs, *args, **kwargs):
    attrs_with_defaults = {}

    for attr_name, attr_metadata in attrs.items():
        attr_default_value_kind = attr_metadata.get(
            "__internal_kind",
            "UNABLE_TO_GET_INTERNAL_KIND"
        )
        if attr_default_value_kind == "string":
            attr_default_value = attr_metadata.get("default", "")
        elif attr_default_value_kind == "list":
            attr_default_value = attr_metadata.get("default", [])
        elif attr_default_value_kind == "dict":
            attr_default_value = attr_metadata.get("default", {})
        elif attr_default_value_kind == "bool":
            attr_default_value = attr_metadata.get("default", False)
        elif attr_default_value_kind == "int":
            attr_default_value = attr_metadata.get("default", 0)
        else:
            attr_default_value = attr_metadata.get("default", None)

        passed_in_attr_value = kwargs.get(attr_name, None)
        if not passed_in_attr_value:
            attr_value = attr_default_value
        else:
            attr_value = passed_in_attr_value

        attrs_with_defaults[attr_name] = attr_value

    repository_ctx = struct(
        attr = struct(**attrs_with_defaults),
        attrs = attrs,
        download = gen_repository_ctx_download(kwargs.get("name")),
        download_and_extract = gen_repository_ctx_download_and_extract(kwargs.get("name")),
        # TODO: implement execute
        execute = lambda *args, **kwargs: struct(
          return_code = 0,
          stderr = "",
          stdout = "",  
        ),
        file = gen_repository_ctx_file(kwargs.get("name")),
        name = kwargs.get("name", "NAME NOT FOUND"),
        # TODO: implement symlink
        symlink = lambda *args, **kwargs: struct(),
        original_name = kwargs.get("name"),
        os = struct(
            environ = {
                "BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN": "1",
            },
            name = "Linux",
            arch = "amd64",
        ),
        path = lambda p: "/home/agondek/projects/github.com/puqu-io/nixcon2026-the-ministry-of-silly-builds-bazel-9-derivation-builder/tmp_out/starlark_modules_cache/" + p,
        # path = lambda p: struct(
        #     # _inner = "/home/agondek/projects/github.com/AleksanderGondek/bzlmod_parser_poc/starlark_modules_cache/" + p,
        #     exists = True,
        # ),
        read = lambda *args: "#<REPOSITORY_CTX_READ_OUTPUT_CONTENTS>",
        template = gen_repository_ctx_template(kwargs.get("name")),
        # TODO: implement which
        which = lambda *args, **kwargs: struct(
             dirname="/dev/null/not-exist",   
        )
    )
    return impl(repository_ctx)


# TODO: This will have to callback Rust code to actually create files on disk, fun!
def repository_rule(
    # impl,
    implementation,
    local = None,
    attrs  = {},
    **repository_rule_kwargs,
):
    return lambda *args, **kwargs: invoke_repository_rule_impl(implementation, attrs, *args, **kwargs)
