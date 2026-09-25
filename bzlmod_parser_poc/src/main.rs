use std::cell::RefCell;
use std::collections::{HashMap, VecDeque};
use std::fs::read_to_string;
use std::io::{Read, Write};
use std::ops::Deref;
use std::os::unix::fs::FileExt;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use anyhow::Error;
use clap::Parser;
use flate2::read::GzDecoder;
use lazy_static::lazy_static;
use sha2::Digest;
use starlark::any::ProvidesStaticType;
use starlark::environment::{
  FrozenModule, GlobalsBuilder, LibraryExtension, Module,
};
use starlark::syntax::Dialect;
use starlark::values::Value;
use starlark::values::none::NoneType;
use starlark::{
  eval::{Evaluator, ReturnFileLoader},
  syntax::AstModule,
};

use bzlmod_parser_poc::bazel_module_lockfile::{
  DownloadRequest, FetchesJsonlEntry, Integrity, Lockfile, SourceSpec,
};

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Args {
  #[arg(short = 'm', long)]
  bzl_module_file: PathBuf,
  #[arg(short = 'l', long)]
  bzl_module_lockfile: PathBuf,
  #[arg(short, long, default_value = "./fetches.jsonl")]
  output: PathBuf,
  #[arg(short, long, default_value = "./starlark_defs/")]
  starlark_defs: PathBuf,
  #[arg(short, long, default_value = "./tmp/")]
  tmp_dir: PathBuf,
}

#[derive(Debug)]
struct ExtensionLoad {
  pub bind_to: String,
  pub from: String,
  pub objects: Vec<String>,
}

static STARLARK_MODULES_CACHE: OnceLock<PathBuf> = OnceLock::new();
fn get_starlark_modules_cache(init_path: Option<PathBuf>) -> PathBuf {
  match init_path {
    None => STARLARK_MODULES_CACHE
      .get()
      .unwrap_or_else(|| {
        panic!("Attempted to read starlark_modules_cache before init")
      })
      .to_path_buf(),
    Some(p) => STARLARK_MODULES_CACHE.get_or_init(|| p).to_path_buf(),
  }
}

pub fn get_executable_path() -> Option<PathBuf> {
  std::fs::read_link("/proc/self/exe").ok()
}

// TODO: Use AST not regex
// TODO: This supports only single bind-extension_loads atm
fn retrieve_extensions_loads<P: AsRef<Path>>(path: P) -> Vec<ExtensionLoad> {
  // CHRIST ALL MIGHTY
  // also I am fucking stupid, only one extension can be 'used' per invocation
  let re =
    regex::Regex::new(r#"(?<bind>\w+)\s*=\s*use_extension\(\s*"(?<from>[\w\d@/:.]+)",(?:\s*"(?<whatOne>[\w\d@/:.]+)",?\s*)(?:\s*"(?<whatTwo>[\w\d@/:.]+)",?\s*)?(?:\s*"(?<whatThree>[\w\d@/:.]+)",?\s*)?\)"#)
      .unwrap();
  let contents =
    std::fs::read_to_string(path.as_ref()).expect("whoopsie, no ready");

  let extension_loads: Vec<ExtensionLoad> = re
    .captures_iter(&contents)
    .map(|caps| {
      let bind = caps.name("bind").unwrap().as_str().to_string();
      let from = caps.name("from").unwrap().as_str().to_string();
      let whatOne = caps.name("whatOne");
      let whatTwo = caps.name("whatTwo");
      let whatThree = caps.name("whatThree");

      let mut objects = Vec::new();
      if let Some(one) = whatOne {
        objects.push(one.as_str().to_string());
      };
      if let Some(two) = whatTwo {
        objects.push(two.as_str().to_string());
      };
      if let Some(three) = whatThree {
        objects.push(three.as_str().to_string());
      };

      ExtensionLoad {
        bind_to: bind,
        from: from,
        objects: objects,
      }
    })
    .collect();

  return extension_loads;
}

// TODO: Replace preable with actual global definitions..
fn parse_bzl_module<P: AsRef<Path>>(
  path: P,
  extra_loads: &Vec<ExtensionLoad>,
  starlark_defs_dir: P,
  starlark_modules_cache: P,
) -> Option<AstModule> {
  let mut preamble = String::default();

  //TODO: AGONDEK LATEST
  if !extra_loads.is_empty() {
    let mut bind_symbol_names: Vec<(String, String)> = Vec::new();
    let mut load_statements: Vec<String> = Vec::new();
    for extra_load in extra_loads {
      let mut symbols_quoted = Vec::<String>::new();
      for symbol in &extra_load.objects {
        symbols_quoted
          .push(format!("_{1}_{0}=\"{0}\"", symbol, extra_load.bind_to));
        bind_symbol_names.push((
          format!("{}.{}", extra_load.from, symbol),
          format!("_{1}_{0}", symbol, extra_load.bind_to),
        ));
      }

      let load_statment: String = format!(
        "load(\"{}\", {})",
        extra_load.from,
        symbols_quoted.join(",")
      );
      load_statements.push(load_statment);
    }

    let febs: Vec<String> = bind_symbol_names
      .iter()
      .map(|(from, to)| format!("\"{from}\": {to}"))
      .collect();
    let febs = format!("FEBS={{{}}}", febs.join(","));

    preamble = load_statements.join("\n") + "\n" + &febs + "\n" + &preamble;
  }
  // TODO: Wait... why does it fail with this?
  else {
    preamble = format!("FEBS={{}}") + "\n" + &preamble;
  }

  if path
    .as_ref()
    .file_stem()
    .map(|x| x.to_os_string() == "MODULE")
    .unwrap_or(false)
  {
    preamble = preamble
      + &read_to_string(starlark_defs_dir.as_ref().join("bzlmod.star")).ok()?;
  };
  preamble = preamble
    + &read_to_string(starlark_defs_dir.as_ref().join("custom.star")).ok()?;

  let bzl_module_contents = read_to_string(&path).ok()?;
  let combined = preamble + "\n" + &bzl_module_contents;

  // eprintln!("");
  // eprintln!("=== DEBUG ===");
  // eprintln!("{combined}");
  // eprintln!("=== END OF DEBUG ==");

  let dialect: Dialect = Dialect {
    enable_def: true,
    enable_lambda: true,
    enable_load: true,
    enable_keyword_only_arguments: true,
    enable_positional_only_arguments: true,
    enable_types: starlark::syntax::DialectTypes::Disable,
    enable_load_reexport: true, // But they plan to change it
    enable_top_level_stmt: false,
    enable_f_strings: false,
    _non_exhaustive: (),
  };

  match AstModule::parse(
    &path
      .as_ref()
      .bazel_label(starlark_modules_cache.as_ref().to_path_buf().as_path()),
    combined,
    &dialect,
  ) {
    Ok(o) => Some(o),
    Err(e) => {
      eprintln!("{e:#?}");
      None
    }
  }
}

fn calculate_cannonical_id_marker(urls: &Vec<String>) -> String {
  // https://github.com/bazelbuild/bazel/blob/c9bf7292d82251ad9a61e1baf53050ccb1787a9c/tools/build_defs/repo/cache.bzl#L25
  // Canonical id marker, without it Bazel complains
  let urls = urls.join(" ");
  let hexdigest = hex::encode(sha2::Sha256::digest(urls.as_bytes()));
  let cannonical_id_marker_name = format!("id-{}", hexdigest);
  cannonical_id_marker_name
}

fn create_canonical_id_marker<P: AsRef<Path>>(
  dest_dir: P,
  request: &DownloadRequest,
) -> PathBuf {
  // https://github.com/bazelbuild/bazel/blob/c9bf7292d82251ad9a61e1baf53050ccb1787a9c/tools/build_defs/repo/cache.bzl#L25
  // Canonical id marker, without it Bazel complains
  // In future, there will be urls, not single url
  let urls = vec![request.url.clone()];
  let cannonical_id_marker_name = calculate_cannonical_id_marker(&urls);

  let cannonical_id_marker_path =
    dest_dir.as_ref().join(cannonical_id_marker_name);

  if let Err(e) = std::fs::File::create(&cannonical_id_marker_path) {
    panic!("{e:#?}");
  }

  cannonical_id_marker_path
}

// TODO: No panic, clean error
fn bazel_repository_cache_download<P: AsRef<Path>>(
  rc_dir: P,
  request: &DownloadRequest,
) -> PathBuf {
  let response = match ureq::get(&request.url).call() {
    Ok(rsp) => rsp,
    Err(e) => {
      panic!("Failed to download {:#?}. Details: {:#?}", request.url, e)
    }
  };

  let target_dir = match &request.integrity {
    Integrity::Sha256(sha256) => rc_dir.as_ref().join(sha256),
  };

  let Ok(_) = std::fs::create_dir_all(&target_dir) else {
    panic!("Failed to create dir: {target_dir:#?}");
  };

  // Bazel names all of downloads as 'file' ffs
  // let target_path = target_dir.join(&request.filename);
  let target_path = target_dir.join("file");

  let Ok(mut target_file) = std::fs::File::create(&target_path) else {
    panic!("Failed to create file: {target_path:#?}");
  };

  // TODO: check if re-reading of the file might be avoided
  let mut response_reader = response.into_body().into_reader();

  let Ok(_) = std::io::copy(&mut response_reader, &mut target_file) else {
    panic!("Failed to copy contents to file {target_path:#?}");
  };

  // Important! Create cannonical id marker

  // TODO: Is not creating it for patchfiles an accident on Bazel side or not?
  // For now, lets keep it in
  match request.kind {
    bzlmod_parser_poc::bazel_module_lockfile::RequestKind::Patchfile => {
      return target_path.to_path_buf();
    }
    _ => (),
  };
  let _ = create_canonical_id_marker(&target_dir, &request);

  target_path.to_path_buf()
}

// TODO: No panic, clean error
fn unpacki_tar_gz<P: AsRef<Path>>(
  target_dir: P,
  archive_path: P,
  spec: &SourceSpec,
) -> Result<(), Error> {
  let archive = std::fs::File::open(archive_path.as_ref())?;
  let mut archive = tar::Archive::new(GzDecoder::new(archive));

  for entry_result in archive.entries()? {
    let mut entry = entry_result?;
    let mut entry_path = entry.path()?.to_path_buf();

    if entry_path.starts_with("./") {
      entry_path = entry_path.strip_prefix("./").unwrap().to_path_buf();
    }
    if let Ok(stripped_path) =
      entry_path.strip_prefix(&spec.strip_prefix.clone().unwrap_or_default())
    {
      let dest_path = target_dir.as_ref().join(stripped_path);

      if let Some(parent) = dest_path.parent() {
        std::fs::create_dir_all(parent)?;
      }
      entry.unpack(dest_path)?;
    }
  }
  Ok(())
}
fn unpacki_tar_xz<P: AsRef<Path>>(
  target_dir: P,
  archive_path: P,
  spec: &SourceSpec,
) -> Result<(), Error> {
  let archive = std::fs::File::open(archive_path.as_ref())?;
  let mut archive = tar::Archive::new(xz::read::XzDecoder::new(archive));

  for entry_result in archive.entries()? {
    let mut entry = entry_result?;
    let mut entry_path = entry.path()?.to_path_buf();

    if entry_path.starts_with("./") {
      entry_path = entry_path.strip_prefix("./").unwrap().to_path_buf();
    }
    if let Ok(stripped_path) =
      entry_path.strip_prefix(&spec.strip_prefix.clone().unwrap_or_default())
    {
      let dest_path = target_dir.as_ref().join(stripped_path);

      if let Some(parent) = dest_path.parent() {
        std::fs::create_dir_all(parent)?;
      }
      entry.unpack(dest_path)?;
    }
  }
  Ok(())
}
fn unpack_zip<P: AsRef<Path>>(
  target_dir: P,
  archive_path: P,
  spec: &SourceSpec,
) -> Result<(), Error> {
  let archive = std::fs::File::open(archive_path.as_ref())?;
  let mut archive = zip::ZipArchive::new(archive)?;

  for i in 0..archive.len() {
    let mut file = archive.by_index(i)?;
    let enclosed_name = file
      .enclosed_name()
      .unwrap_or_else(|| panic!("enclosed name dead"));

    if let Ok(stripped_path) =
      enclosed_name.strip_prefix(&spec.strip_prefix.clone().unwrap_or_default())
    {
      if stripped_path.as_os_str().is_empty() {
        continue;
      }

      let dest_path = target_dir.as_ref().join(stripped_path);
      if file.is_dir() {
        std::fs::create_dir_all(&dest_path)?;
      } else {
        // Ensure parent folders exist before writing the file
        if let Some(parent) = dest_path.parent() {
          if !parent.exists() {
            std::fs::create_dir_all(parent)?;
          }
        }
        // Write the file to disk
        let mut outfile = std::fs::File::create(&dest_path)?;
        std::io::copy(&mut file, &mut outfile)?;
      }
    }
  }
  Ok(())
}

fn apply_patch<P: AsRef<Path>>(
  target_dir: P,
  patchfile: P,
  spec: &SourceSpec,
) -> Result<(), Error> {
  let res: Result<std::process::Output, std::io::Error>;
  if let Some(p) = spec.patch_strip {
    res = std::process::Command::new("patch")
      .arg(format!("-p{}", p))
      .arg("-d")
      .arg(target_dir.as_ref())
      .arg("-i")
      .arg(patchfile.as_ref())
      .output();
  } else {
    res = std::process::Command::new("patch")
      .arg("-d")
      .arg(target_dir.as_ref())
      .arg("-i")
      .arg(patchfile.as_ref())
      .output();
  };

  match res {
    Ok(result) => {
      if !result.status.success() {
        panic!("{:#?}", String::from_utf8_lossy(&result.stderr));
      }
    }
    Err(e) => panic!("{e:#?}"),
  }
  Ok(())
}

// TODO: Improve
fn copy_bazel_builtin_repos<P: AsRef<Path>>(
  target_dir: P,
  source_dir: P,
) -> Result<(), Error> {
  let res: Result<std::process::Output, std::io::Error>;
  res = std::process::Command::new("cp")
    .arg("-r")
    .arg("-f")
    .arg(source_dir.as_ref())
    .arg(target_dir.as_ref())
    .output();

  match res {
    Ok(result) => {
      if !result.status.success() {
        panic!("{:#?}", String::from_utf8_lossy(&result.stderr));
      }
    }
    Err(e) => panic!("{e:#?}"),
  }

  Ok(())
}

// TODO: Improve
fn evaluate_bzl_module<P: AsRef<Path>>(
  filepath: P,
  load_as: Option<String>,
  downloads_registry: &mut std::collections::HashSet<DownloadRequest>,
  initialized_module_bzls: &mut std::collections::HashSet<PathBuf>,
  depth: usize,
  // TODO: This is just nasty..
  loaded_modules: &mut HashMap<String, FrozenModule>,
  starlark_defs_dir: P,
  starlark_modules_cache: P,
) -> starlark::Result<FrozenModule> {
  let filepath = filepath.as_ref();
  let filepath_to_load_from = if !filepath.is_bazel_label() {
    filepath.to_path_buf()
  } else {
    filepath
      .to_string_lossy()
      .to_string()
      .starlark_module_path(starlark_modules_cache.as_ref())
  };

  // eprintln!("===");
  eprintln!(
    "{}evaluate_bzl_module: {:#?} start",
    " ".repeat(depth),
    filepath
  );
  // eprintln!(
  //   "Attemtping to load filepath.is_bazel_label: {:#?}",
  //   filepath.is_bazel_label()
  // );
  // eprintln!(
  //   "Attempting to load filepath_to_load_from: {:#?}",
  //   filepath_to_load_from
  // );
  // eprintln!(" ");

  // TODO: Not sure if seen should be above or after
  // Hello, I will not try to load corresponding MODULE.bazel file

  // if filepath_to_load_from
  //   .file_name()
  //   .map_or(true, |filename| filename != "MODULE.bazel")
  // {
  //   let corresponding_module_bazel = filepath_to_load_from
  //     .to_string_lossy()
  //     .to_string()
  //     .starlark_module_path()
  //     .starlark_module_ruleset_path()
  //     .join("MODULE.bazel");
  //   if corresponding_module_bazel.exists() {
  //     if !initialized_module_bzls.contains(&corresponding_module_bazel) {
  //       eprintln!(
  //         "{}evaluate_bzl_module: {:#?} will subeval: {:#?}",
  //         " ".repeat(depth),
  //         filepath,
  //         &corresponding_module_bazel,
  //       );

  //       initialized_module_bzls.insert(corresponding_module_bazel.clone());

  //       match evaluate_bzl_module(
  //         corresponding_module_bazel.clone(),
  //         None,
  //         downloads_registry,
  //         initialized_module_bzls,
  //         depth + 1,
  //         loaded_modules,
  //       ) {
  //         Err(err) => {
  //           eprintln!("Failed to evaluate: {:#?}", &corresponding_module_bazel);
  //           eprintln!("Details: {err:#?}");
  //           panic!("unable to evaluate!");
  //         }
  //         Ok(o) => (), //eprintln!("What! {o:#?}"),
  //       }
  //       // Prevent cyclic loads
  //       // seen_module_bzl_files.insert(corresponding_module_bazel.clone());
  //     } else {
  //       eprintln!(
  //         "{}evaluate_bzl_module: {:#?} skipping subeval: {:#?}",
  //         " ".repeat(depth),
  //         filepath,
  //         &corresponding_module_bazel,
  //       );

  //       // eprintln!(
  //       //   "Wanted to evaluate {:#?} but it was already evaluated.",
  //       //   &corresponding_module_bazel
  //       // );
  //     }
  //   } else {
  //     eprintln!(
  //       "Wanted to evaluate {:#?} but it was not found.",
  //       &corresponding_module_bazel
  //     )
  //   }
  // }

  // Hello, I have now stopped trying to load corresponding MODULE.bazel file

  let extension_loads: Vec<ExtensionLoad>;
  if filepath.file_stem().map_or(false, |fs| fs == "MODULE") {
    extension_loads = retrieve_extensions_loads(&filepath_to_load_from);
  } else {
    extension_loads = Vec::default();
  }

  eprintln!(
    "{}evaluate_bzl_module: {:#?} parse. Extension loads: {:#?}",
    " ".repeat(depth),
    filepath,
    &extension_loads,
  );

  let Some(ast) = parse_bzl_module(
    &filepath_to_load_from,
    &extension_loads,
    &starlark_defs_dir.as_ref().to_path_buf(),
    &starlark_modules_cache.as_ref().to_path_buf(),
  ) else {
    // TODO: Improve
    eprintln!("filepath: {:#?}", filepath);
    eprintln!("filepath.is_bazel_label: {:#?}", filepath.is_bazel_label());
    eprintln!("filepath_to_load_from: {:#?}", filepath_to_load_from);
    panic!(
      "failed to load module from path {:#?}",
      filepath_to_load_from
    );
  };

  // let mut loaded_modules = HashMap::<String, FrozenModule>::new();
  for load in ast.loads() {
    let full_module_id =
      if let Some(stripped) = load.module_id.strip_prefix("//") {
        // If loading relative path, swap it to full path, but register as shortened
        filepath
          .to_string_lossy()
          .to_string()
          .starlark_module_path(starlark_modules_cache.as_ref())
          .starlark_module_ruleset_path(starlark_modules_cache.as_ref())
          .join(stripped.replace(":", "/"))
          .bazel_label(starlark_modules_cache.as_ref())
      } else if let Some(stripped) = load.module_id.strip_prefix(":") {
        filepath
          .to_string_lossy()
          .to_string()
          .starlark_module_path(starlark_modules_cache.as_ref())
          .parent()
          .expect("no parent, so sad")
          .join(stripped)
          .bazel_label(starlark_modules_cache.as_ref())
      } else {
        load.module_id.to_string()
      };

    // TODO: agondek: latest
    // Add parsing of MODULE.bazel of loaded stuff, to ensure extensions create stuff

    if !loaded_modules.contains_key(load.module_id) {
      let mut x = loaded_modules.clone();
      loaded_modules.insert(
        load.module_id.to_owned(),
        evaluate_bzl_module(
          full_module_id,
          Some(load.module_id.to_string()),
          downloads_registry,
          initialized_module_bzls,
          depth + 1,
          &mut x,
          starlark_defs_dir.as_ref().to_string_lossy().to_string(),
          starlark_modules_cache
            .as_ref()
            .to_string_lossy()
            .to_string(),
        )?,
      );
    }
  }

  let loaded_modules_refs: HashMap<&str, &FrozenModule> = loaded_modules
    .iter()
    .map(|(k, v)| (k.as_str(), v))
    .collect();
  let mut loader = ReturnFileLoader {
    modules: &loaded_modules_refs,
  };

  // TODO: Use those, especially partial
  // SIC! :)
  // LibraryExtension::Json
  // LibraryExtension::Partial
  // LibraryExtension::StructType
  let globals = GlobalsBuilder::extended_by(&[
    LibraryExtension::StructType,
    LibraryExtension::SetType,
  ])
  .with(starlark_report_download)
  .with(starlark_rctx_file)
  .with(starlark_panic)
  .with(starlark_print)
  .with_namespace("json", starlark_json_members)
  .build();

  let downloads_ledger = DownloadsLedger::default();

  eprintln!(
    "{}evaluate_bzl_module: {:#?} eval",
    " ".repeat(depth),
    filepath
  );

  Module::with_temp_heap(|module| {
    {
      let mut eval = Evaluator::new(&module);
      eval.set_loader(&mut loader);
      eval.extra = Some(&downloads_ledger);
      eval.eval_module(ast, &globals)?;
    }
    // Step 2. Store all download calls
    {
      downloads_registry.extend(downloads_ledger.0.into_inner());
    }

    Ok(module.freeze_named(starlark::values::FrozenHeapName::User(
      Box::new(
        load_as.unwrap_or_else(|| filepath.to_string_lossy().to_string()),
      ),
    ))?)
  })
}

// Quick and dirty Label to Path and Path To String
pub trait AsBazelLabel {
  fn bazel_label(&self, starlark_modules_cache: &Path) -> String;
  fn is_bazel_label(&self) -> bool;
  fn starlark_module_ruleset_path(
    &self,
    starlark_modules_cache: &Path,
  ) -> PathBuf;
}
pub trait AsStarlarkModulePath {
  fn starlark_module_path(&self, starlark_modules_cache: &Path) -> PathBuf;
}

impl<T> AsBazelLabel for T
where
  T: AsRef<Path>,
{
  fn bazel_label(&self, starlark_modules_cache: &Path) -> String {
    // TODO: this is copied over
    let root = starlark_modules_cache;
    let path = self.as_ref();
    let Ok(path) = path.strip_prefix(root) else {
      // TODO: this will maybe brak something
      // eprintln!("{:#?} does not start with {:#?}", path, root);
      let lbl = format!(
        "//{}",
        path.file_name().unwrap().to_string_lossy().to_string()
      );
      return lbl;
    };
    // Rolling dumb and wrong impl
    let path = path.to_string_lossy().to_string();
    let mut comp: VecDeque<String> =
      path.split("/").map(|s| s.to_string()).collect();
    let ruleset_name = comp.pop_front().expect("a");
    let filename = comp.pop_back().expect("b");
    let lbl = format!(
      "@{}//{}:{}",
      ruleset_name,
      comp.into_iter().collect::<Vec<_>>().join("/"),
      filename
    );
    lbl
  }
  fn starlark_module_ruleset_path(
    &self,
    starlark_modules_cache: &Path,
  ) -> PathBuf {
    // TODO: this is copied over
    let root = starlark_modules_cache;
    let path = self.as_ref();
    let Ok(path) = path.strip_prefix(root) else {
      // TODO: this will maybe brak something
      panic!("{:#?} does not start with {:#?}.EElo", path, root);
    };
    // Rolling dumb and wrong impl
    let path = path.to_string_lossy().to_string();
    let mut comp: VecDeque<String> =
      path.split("/").map(|s| s.to_string()).collect();
    let ruleset_name = comp.pop_front().expect("aa23");
    root.join(ruleset_name).to_path_buf()
  }
  fn is_bazel_label(&self) -> bool {
    //Heh, if only it was that simple
    self.as_ref().to_string_lossy().to_string().starts_with("@")
  }
}

impl<T> AsStarlarkModulePath for T
where
  T: AsRef<str>,
{
  fn starlark_module_path(&self, starlark_modules_cache: &Path) -> PathBuf {
    // TODO: this is copied over
    let root = starlark_modules_cache;
    root
      .join(
        self
          .as_ref()
          .replacen("@", "", 1)
          .replacen("//", "/", 1)
          .replacen(":", "/", 1),
      )
      .to_path_buf()
  }
}

// Reporting of downloads from extensions
#[derive(Debug, ProvidesStaticType, Default)]
struct DownloadsLedger(RefCell<std::collections::HashSet<DownloadRequest>>);

impl DownloadsLedger {
  pub fn add(
    &self,
    filename: String,
    integrity: String,
    kind: String,
    url: String,
  ) -> () {
    self.0.borrow_mut().insert(DownloadRequest {
      filename: filename,
      integrity: Integrity::Sha256(integrity),
      kind: bzlmod_parser_poc::bazel_module_lockfile::RequestKind::Archive,
      url: url,
    });
  }
}

#[starlark::starlark_module]
fn starlark_report_download(builder: &mut GlobalsBuilder) {
  fn bazel_report_download(
    filename: String,
    integrity: String,
    kind: String,
    url: String,
    eval: &mut Evaluator,
  ) -> anyhow::Result<NoneType> {
    let downloads_ledger = eval
      .extra
      .unwrap_or_else(|| panic!("Could not retrieve eval.extra"))
      .downcast_ref::<DownloadsLedger>()
      .unwrap_or_else(|| panic!("Could not downcast to DownloadsLedger"));

    downloads_ledger.add(filename, integrity, kind, url);

    Ok(NoneType)
  }
}

#[starlark::starlark_module]
fn starlark_rctx_file(builder: &mut GlobalsBuilder) {
  fn bazel_rctx_file(
    repository_name: String,
    path: String,
    content: Option<String>,
    executable: Option<bool>,
    legacy_utf8: Option<bool>,
    eval: &mut Evaluator,
  ) -> anyhow::Result<NoneType> {
    let content = content.unwrap_or(String::default());
    let executable = executable.unwrap_or(true);

    let full_path = get_starlark_modules_cache(None)
      .join(repository_name)
      .join(path);

    let dirs = full_path
      .parent()
      .expect("Scaresly beliveable that this will be without parent");

    let _ = std::fs::create_dir_all(dirs);
    let _ = std::fs::write(full_path, content);

    Ok(NoneType)
  }
}

#[starlark::starlark_module]
fn starlark_panic(builder: &mut GlobalsBuilder) {
  fn panic(x: Value, eval: &mut Evaluator) -> anyhow::Result<NoneType> {
    panic!("[ALEX PANIC]: {:#?}", x.to_json()?);
    Ok(NoneType)
  }
}

// TODO: This does not seem to print? :<
#[starlark::starlark_module]
fn starlark_print(builder: &mut GlobalsBuilder) {
  fn print(x: Value, eval: &mut Evaluator) -> anyhow::Result<NoneType> {
    eprintln!("[ALEX Print]: {:#?}", x.to_json()?);
    Ok(NoneType)
  }
}

#[starlark::starlark_module]
fn starlark_json_members(globals: &mut GlobalsBuilder) {
  fn encode(#[starlark(require = pos)] x: Value) -> anyhow::Result<String> {
    x.to_json()
  }

  fn decode<'v>(
    #[starlark(require = pos)] x: &str,
    heap: starlark::values::Heap<'v>,
  ) -> anyhow::Result<Value<'v>> {
    Ok(heap.alloc(serde_json::from_str::<serde_json::Value>(x)?))
  }
}

fn main() {
  let args = Args::parse();

  const SKIP_PREP: bool = false;

  let mut all_downloads: std::collections::HashSet<DownloadRequest> =
    std::collections::HashSet::default();

  let lf = std::fs::File::open(&args.bzl_module_lockfile).expect("bbb");
  let lb = std::io::BufReader::new(lf);

  let Ok(lockfile) =
    serde_json::from_reader::<std::io::BufReader<std::fs::File>, Lockfile>(lb)
  else {
    eprintln!("Could not read lockfile");
    std::process::exit(1);
  };

  let starlark_modules_root = args.tmp_dir.join("starlark_modules_cache");
  // TODO: SIC
  let _ = std::fs::create_dir_all(&starlark_modules_root);
  let _ = get_starlark_modules_cache(Some(starlark_modules_root.to_path_buf()));

  let rc_dir = args.tmp_dir.join("repo_cache/content_addressable/sha256");
  if !SKIP_PREP {
    let mut starlark_modules: HashMap<String, SourceSpec> = HashMap::default();

    for r in lockfile.registry_files_downloads() {
      all_downloads.insert(r.clone());
      let downloaded_file = bazel_repository_cache_download(&rc_dir, &r);
      if !matches!(
        r.kind,
        bzlmod_parser_poc::bazel_module_lockfile::RequestKind::Source
      ) {
        continue;
      }

      let Ok(source_json_contents) = std::fs::read_to_string(&downloaded_file)
      else {
        panic!("Failed to load contents of {downloaded_file:#?}");
      };
      let Ok(source_json) =
        serde_json::from_str::<SourceSpec>(&source_json_contents)
      else {
        panic!("Failed to deserialize {downloaded_file:#?}");
      };

      let Some(filename) = Path::new(&source_json.url).file_name() else {
        panic!("Could not obtain filename for {:#?}", &source_json.url);
      };

      let source_json_dr = DownloadRequest {
        filename: filename.to_string_lossy().to_string(),
        integrity: source_json.integrity.clone(),
        kind: bzlmod_parser_poc::bazel_module_lockfile::RequestKind::Archive,
        url: source_json.url.clone(),
      };

      let _downloaded_archive_file =
        bazel_repository_cache_download(&rc_dir, &source_json_dr);
      all_downloads.insert(source_json_dr.clone());

      for (patchfile_name, integrity) in
        &source_json.patches.clone().unwrap_or(HashMap::default())
      {
        let patchfile_dr = DownloadRequest {
          filename: patchfile_name.clone(),
          integrity: integrity.clone(),
          kind:
            bzlmod_parser_poc::bazel_module_lockfile::RequestKind::Patchfile,
          // The download url for patches is always:
          // <original_url_without_filename> + "patches/" + <patchfilename>
          url: format!(
            "{}patches/{}",
            r.url.replacen(&r.filename, "", 1),
            patchfile_name
          ),
        };
        // eprintln!("{patchfile_dr:#?}");
        let _ = bazel_repository_cache_download(&rc_dir, &patchfile_dr);
        all_downloads.insert(patchfile_dr.clone());
      }

      for (overlay_filename, overlay_integrity) in
        &source_json.overlay.clone().unwrap_or(HashMap::default())
      {
        let overlay_dr = DownloadRequest {
          filename: overlay_filename.clone(),
          integrity: overlay_integrity.clone(),
          kind: bzlmod_parser_poc::bazel_module_lockfile::RequestKind::Overlay,
          // The download url for patches is always:
          // <original_url_without_filename> + "patches/" + <patchfilename>
          url: format!(
            "{}overlay/{}",
            r.url.replacen(&r.filename, "", 1),
            overlay_filename
          ),
        };
        // eprintln!("{patchfile_dr:#?}");
        let _ = bazel_repository_cache_download(&rc_dir, &overlay_dr);
        all_downloads.insert(overlay_dr.clone());
      }

      // TODO: Improve, this name might be changed via top-level MODULE.bazel
      // TODO: The registry might be different
      let repository_name = r
        .url
        .replacen("https://bcr.bazel.build/modules/", "", 1)
        .replace("-", "_");
      let repository_name = repository_name
        .split("/")
        .next()
        .expect("Could not get repository name");

      starlark_modules.insert(repository_name.to_string(), source_json);
    }

    // ==================================
    // || Load modules for interpreter ||
    // ==================================

    // TODO: we need to inject @bazel_tools repo etc
    let _ = copy_bazel_builtin_repos(
      starlark_modules_root.join("bazel_tools"),
      args.starlark_defs.join("bazel_tools"),
    );

    for (repo_name, specs) in &starlark_modules {
      let repo_dir = starlark_modules_root.join(repo_name);

      let Ok(_) = std::fs::create_dir_all(&repo_dir) else {
        panic!("Failed to create dir: {repo_dir:#?}");
      };

      // 1. Unpack and strip_prefix
      // Bazel names all outputs as 'file' ffs
      // we use original name to work out the extension
      let og_archive_filepath = Path::new(&specs.url);
      let archive_filename = "file";
      let archive_path = match &specs.integrity {
        Integrity::Sha256(sha256) => rc_dir.join(sha256).join(archive_filename),
      };

      let r = match og_archive_filepath
        .extension()
        .map(|e| e.to_str())
        .flatten()
      {
        // TODO: just tar vs tar.gz and others
        Some("zip") => unpack_zip(&repo_dir, &archive_path, specs),
        _ => unpacki_tar_gz(&repo_dir, &archive_path, specs),
      };

      let Ok(_) = r else {
        panic!("Unable to unpack archive {archive_path:#?}");
      };
      // 2. Apply patches
      // TODO: those are not ordered? wtf
      for (_patchfile_name, integrity) in
        &specs.patches.clone().unwrap_or_default()
      {
        // Bazel names all outputs as 'file' ffs
        let patchfile = match integrity {
          Integrity::Sha256(sha256) => rc_dir.join(sha256).join("file"),
        };
        let Ok(_) = apply_patch(&repo_dir, &patchfile, &specs) else {
          panic!("patching failed. {patchfile:#?}");
        };
      }
      // !!! TODO: agondek
      // /// apply overlay files
    }
  }
  // 3. Persist information for use in starlark interpreter
  // TODO: Do I really need it though? This can be lazy
  // for entry in walkdir::WalkDir::new(&starlark_modules_root)
  //   .into_iter()
  //   .filter_entry(|entry| {
  //     !entry.file_type().is_dir()
  //       && entry.path().extension().map(|ext| ext == "bzl").unwrap()
  //   })
  // {
  //   let Ok(entry) = entry else {
  //     continue;
  //   }
  // }

  // ========================
  // || Beloew Stalark fun ||
  // ========================

  // Final
  let modulefile_path = args.bzl_module_file;

  let mut downloads_registry =
    std::collections::HashSet::<DownloadRequest>::new();
  let mut initialized_module_bzls = std::collections::HashSet::<PathBuf>::new();
  let mut loaded_modules = HashMap::<String, FrozenModule>::new();
  match evaluate_bzl_module(
    &modulefile_path,
    None,
    &mut downloads_registry,
    &mut initialized_module_bzls,
    0,
    &mut loaded_modules,
    &args.starlark_defs,
    &starlark_modules_root,
  ) {
    Ok(_ret) => eprintln!("Evaluated {:#?}", &modulefile_path),
    Err(e) => eprintln!("Error. {e:#?}"),
  }

  println!("=== Registered Download invocations ===");
  println!("{downloads_registry:#?}");

  for request in &downloads_registry {
    bazel_repository_cache_download(&rc_dir, request);
    all_downloads.insert(request.clone());
  }

  // Serialize the lockfile
  let mut fetchesjsonl_lines = Vec::<String>::new();
  for request in &all_downloads {
    let urls = vec![request.url.clone()];
    let entry = FetchesJsonlEntry {
      canonical_id_marker: Some(calculate_cannonical_id_marker(&urls)),
      urls: urls,
      sha256: match &request.integrity {
        Integrity::Sha256(sha256) => sha256.clone(),
      },
      context: "bzlmod_parser_poc".to_string(),
      kind: "archive".to_string(), // SIC! needs improvements
    };
    fetchesjsonl_lines
      .push(serde_json::to_string(&entry).expect("no serializetion"));
  }

  let _ = std::fs::write(args.output, fetchesjsonl_lines.join("\n"));
}
