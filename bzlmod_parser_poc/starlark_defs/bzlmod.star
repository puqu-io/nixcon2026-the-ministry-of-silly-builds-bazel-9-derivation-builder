def ignore(*args, **kwargs):
    pass

def archive_override(*args, **kwargs):
    # return notice(*args, **kwargs)
    pass

def bazel_dep(*args, **kwargs):
    # return notice(*args, **kwargs)
    pass

def flag_alias(*args, **kwargs):
     # return ignore(*args, **kwargs)   
    pass

def git_override(*args, **kwargs):
    # return notice(*args, **kwargs)
    pass

def include(*args, **kwargs):
    # return notice(*args, **kwargs)
    pass

def inject_repo(*args, **kwargs):
    # return notice(*args, **kwargs)
    pass
 
def local_path_override(*args, **kwargs):
    # return notice(*args, **kwargs)
    pass

def module(*args, **kwargs):
    # return ignore(*args, **kwargs)
    pass

def multiple_version_override(*args, **kwargs):
    # return notice(*args, **kwargs)
    pass

def override_repo(*args, **kwargs):
    # return notice(*args, **kwargs)
    pass

def register_execution_platforms(*args, **kwargs):
    # return ignore(*args, **kwargs)
    pass

def register_toolchains(*args, **kwargs):
    # return ignore(*args, **kwargs)
    pass

def single_version_override(*args, **kwargs):
    # return notice(*args, **kwargs)
    pass

def use_extension(*args, **kwargs):
    if kwargs.get("dev_dependency", False):
        return struct(
            toolchain=lambda **kwargs: struct(),
            from_file=lambda **kwargs: struct(),
            host=lambda **kwargs: struct(),
        )

    eb = FEBS.get("{}.{}".format(args[0],args[1]))
    if str(type(eb)) == "function":
        # For non tag_classes and simple extensions
        eb()

    return eb

def use_repo(*args, **kwargs):
    # TODO: This will be failing for now
    # args are functions which do not serialize
    # return notice(*args, **kwargs)]\
    # for arg in args:
    #     fun = FEBS.get(arg, "AAAA")
    #     panic(FEBS)
    #     fun()
    # if args[1] == "bazel_features_globals":
        # panic(args)
    pass

def use_repo_rule(*args, **kwargs):
    # return notice(*args, **kwargs)
    pass
