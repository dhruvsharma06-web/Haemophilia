{{flutter_js}}
{{flutter_build_config}}

// Use a fresh entrypoint URL when replacing a previously cached admin release.
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath += '?release=doctor-approvals-2';
  }
}
_flutter.loader.load();
