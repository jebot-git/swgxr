"""Environment for SWGXR Godot processes, without external OBS capture injection."""
import os


def client_environment(source=None):
    environment = dict(os.environ if source is None else source)
    # These are the capture layers' own loader-manifest disable switches.
    # Set before Godot starts: OpenXR/Vulkan load layers before project scripts.
    environment['DISABLE_XR_APILAYER_NOVENDOR_OBSMirror'] = '1'
    environment['DISABLE_OBS_VKCAPTURE'] = '1'
    environment.pop('OBS_VKCAPTURE', None)
    return environment
