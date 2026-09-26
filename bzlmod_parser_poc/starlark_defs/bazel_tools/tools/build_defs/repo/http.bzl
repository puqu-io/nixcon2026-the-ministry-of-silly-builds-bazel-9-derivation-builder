def http_file(*args, **kwargs):
    urls = kwargs.get("urls", [kwargs.get("url", "no url found")])
    sha256 = kwargs.get("sha256", kwargs.get("integrity", "no integrity found"))

    # print("repository_ctx.download_and_extract called with: url:{} sha256:{}".format(url, sha256))
    # TODO: download_and_extract might have urls and integrity and ...
    bazel_report_download(
        urls[0].rsplit("/", 1)[-1],
        sha256,
        "<kind-to-be-used-2>",
        " ".join(urls),
    )
    return

def http_archive(*args, **kwargs):
    urls = kwargs.get("urls", [kwargs.get("url", "no url found")])
    sha256 = kwargs.get("sha256", kwargs.get("integrity", "no integrity found"))

    # print("repository_ctx.download_and_extract called with: url:{} sha256:{}".format(url, sha256))
    # TODO: download_and_extract might have urls and integrity and ...
    bazel_report_download(
        urls[0].rsplit("/", 1)[-1],
        sha256,
        "<kind-to-be-used-3>",
        " ".join(urls),
    )
    return
