"""Utilities"""
load("@bazel_skylib//lib:versions.bzl", "versions")

def _parse_image(image):
    """Support syntax sugar in oci_pull where multiple data fields are in a single string, "image"

    Args:
        image: full-qualified reference url
    Returns:
        a tuple containing  scheme, registry, repository, digest, and tag information.
    """

    scheme = "https"
    digest = None
    tag = None

    if image.startswith("http://"):
        image = image[len("http://"):]
        scheme = "http"
    if image.startswith("https://"):
        image = image[len("https://"):]

    # Check syntax sugar for digest/tag suffix on image
    if image.rfind("@") > 0:
        image, digest = image.rsplit("@", 1)

    # Check if the last colon has no slashes after it.
    # Matches debian:latest and myregistry:8000/myimage:latest
    # but does not match myregistry:8000/myimage
    colon = image.rfind(":")
    if colon > 0 and image[colon:].find("/") == -1:
        image, tag = image.rsplit(":", 1)

    # Syntax sugar, special case for dockerhub
    if image.startswith("docker.io/"):
        image = "index." + image

    # If image has no repository, like bare "ubuntu" we assume it's dockerhub
    if image.find("/") == -1:
        image = "index.docker.io/library/" + image
    registry, repository = image.split("/", 1)

    return (scheme, registry, repository, digest, tag)

def _sha256(rctx, path):
    """Returns SHA256 hashsum of file at path

    Args:
        rctx: repository context
        path: path to the file
    Returns:
        hashsum of file
    """

    # Attempt to use the first viable method to calculate the SHA256 sum. sha256sum is part of
    # coreutils on Linux, but is not available on MacOS. shasum is a perl script that is available
    # on MacOS, but is not necessarily always available on Linux. OpenSSL is used as a final
    # fallback if neither are available
    result = rctx.execute(["shasum", "-a", "256", path])
    if result.return_code == 127:  # 127 return code indicates command not found
        result = rctx.execute(["sha256sum", path])
    if result.return_code == 127:
        result = rctx.execute(["openssl", "sha256", "-r", path])
    if result.return_code:
        msg = "sha256 failed: \nSTDOUT:\n%s\nSTDERR:\n%s" % (result.stdout, result.stderr)
        fail(msg)

    return result.stdout.split(" ", 1)[0]

def _warning(rctx, message):
    rctx.execute([
        "echo",
        "\033[0;33mWARNING:\033[0m {}".format(message),
    ], quiet = False)

def _maybe_wrap_launcher_for_windows(ctx, bash_launcher):
    """Windows cannot directly execute a shell script.

    Wrap with a .bat file that executes the shell script with a bash command.
    Based on create_windows_native_launcher_script from
    https://github.com/aspect-build/bazel-lib/blob/main/lib/windows_utils.bzl
    but without requiring that the script has a .runfiles folder.

    To use:
    - add the _windows_constraint appears in the rule attrs
    - make sure the bash_launcher is in the inputs to the action
    - @bazel_tools//tools/sh:toolchain_type should appear in the rules toolchains
    """

    return bash_launcher

def _file_exists(rctx, path):
    result = rctx.execute(["stat", path])
    return result.return_code == 0

_INDEX_JSON_TMPL = """\
{{
   "schemaVersion": 2,
   "mediaType": "application/vnd.oci.image.index.v1+json",
   "manifests": [
      {{
         "mediaType": "{}",
         "size": {},
         "digest": "{}"{optional_platform}
      }}
   ]
}}"""

def _build_manifest_json(media_type, size, digest, platform):
    optional_platform = ""

    if platform:
        platform_parts = platform.split("/", 3)

        optional_variant = ""
        if len(platform_parts) == 3:
            optional_variant = ''',
            "variant": "{}"'''.format(platform_parts[2])

        optional_platform = """,
         "platform": {{
            "architecture": "{}",
            "os": "{}"{optional_variant}
         }}""".format(platform_parts[1], platform_parts[0], optional_variant = optional_variant)

    return _INDEX_JSON_TMPL.format(
        media_type,
        size,
        digest,
        optional_platform = optional_platform,
    )

def _assert_crane_version_at_least(ctx, at_least, rule):
    toolchain = ctx.toolchains["@rules_oci//oci:crane_toolchain_type"]
    if not versions.is_at_least(at_least, toolchain.crane_info.version):
        fail("rule {} requires crane version >={}".format(rule, at_least))


util = struct(
    parse_image = _parse_image,
    sha256 = _sha256,
    warning = _warning,
    maybe_wrap_launcher_for_windows = _maybe_wrap_launcher_for_windows,
    file_exists = _file_exists,
    build_manifest_json = _build_manifest_json,
    assert_crane_version_at_least = _assert_crane_version_at_least
)
