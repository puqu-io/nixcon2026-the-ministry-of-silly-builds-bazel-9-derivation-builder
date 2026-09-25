use std::{collections::HashMap, path::PathBuf};

use base64::Engine;
use serde::Deserialize;

// TODO: Beautiful name, much wow
#[derive(Debug, serde::Serialize, Clone)]
pub struct FetchesJsonlEntry {
  pub canonical_id_marker: Option<String>,
  pub urls: Vec<String>,
  pub sha256: String,
  pub context: String,
  pub kind: String,
}

// TODO: Represent all urls as URL from url crate :)

#[derive(Debug, Deserialize, Clone)]
#[serde(untagged)]
enum JsonValue {
  Boolean(bool),
  Number(i32),
  String(String),
  Vec(Vec<JsonValue>),
  Dict(HashMap<String, JsonValue>),
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct GeneratedRepoSpec {
  repo_rule_id: String,
  attributes: HashMap<String, JsonValue>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ModuleExtension {
  bzl_transitive_digest: String,
  usages_digest: String,
  recorded_inputs: Vec<String>,
  generated_repo_specs: HashMap<String, GeneratedRepoSpec>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ModuleExtensionWrapper {
  general: ModuleExtension,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Lockfile {
  lock_file_version: u32,
  registry_file_hashes: HashMap<String, String>,
  selected_yanked_versions: HashMap<String, String>,
  module_extensions: HashMap<String, ModuleExtensionWrapper>,
  facts: HashMap<String, HashMap<String, HashMap<String, Vec<String>>>>,
}

// Other thing ...
//
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Integrity {
  Sha256(String),
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum RequestKind {
  Archive,
  Module,
  Overlay,
  Patchfile,
  Source,
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
pub struct DownloadRequest {
  pub filename: String,
  pub integrity: Integrity,
  pub kind: RequestKind,
  pub url: String,
}

#[derive(Debug, Deserialize)]
pub struct SourceSpec {
  pub docs_url: Option<String>,
  pub integrity: Integrity,
  pub strip_prefix: Option<String>,
  pub url: String,
  pub patches: Option<HashMap<String, Integrity>>,
  pub patch_strip: Option<u8>,
  pub overlay: Option<HashMap<String, Integrity>>,
}

impl<'de> serde::Deserialize<'de> for Integrity {
  fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
  where
    D: serde::Deserializer<'de>,
  {
    struct IntegrityVisitor;

    impl<'de> serde::de::Visitor<'de> for IntegrityVisitor {
      type Value = Integrity;

      fn expecting(
        &self,
        formatter: &mut std::fmt::Formatter,
      ) -> std::fmt::Result {
        formatter.write_str("a string starting with 'sha256'")
      }

      fn visit_str<E>(self, v: &str) -> Result<Self::Value, E>
      where
        E: serde::de::Error,
      {
        if let Some(integrity) = v.strip_prefix("sha256-") {
          let r = base64::prelude::BASE64_STANDARD
            .decode(integrity)
            .expect("fix me");
          let hex_string = hex::encode(r);
          return Ok(Integrity::Sha256(hex_string));
        }
        Err(serde::de::Error::invalid_value(
          serde::de::Unexpected::Str(v),
          &self,
        ))
      }
    }

    deserializer.deserialize_str(IntegrityVisitor)
  }
}

impl Lockfile {
  pub fn registry_files_downloads(&self) -> Vec<DownloadRequest> {
    self
      .registry_file_hashes
      .iter()
      .map(|(url, sha256)| {
        let filename = std::path::Path::new(url)
          .file_name()
          .map(|s| s.to_string_lossy().to_string())
          .expect("grrrr");

        let is_source = filename == "source.json";
        DownloadRequest {
          filename: filename,
          integrity: Integrity::Sha256(sha256.clone()),
          kind: match is_source {
            true => RequestKind::Source,
            _ => RequestKind::Module,
          },
          url: url.clone(),
        }
      })
      .collect()
    //   let actually_used = self.registry_file_hashes.iter().filter(|(url, _)| {
    //     // TODO: You are doing the same thing twice bro
    //     let filename = std::path::Path::new(url)
    //       .file_name()
    //       .map(|s| s.to_string_lossy().to_string())
    //       .expect("grrrri2");
    //     if filename == "source.json" {
    //       return self.registry_file_hashes.contains_key(&url.replacen(
    //         "source.json",
    //         "MODULE.bazel",
    //         1,
    //       ));
    //     }
    //     self.registry_file_hashes.contains_key(&url.replacen(
    //       "MODULE.bazel",
    //       "source.json",
    //       1,
    //     ))
    //   });

    //   actually_used
    //     .map(|(url, sha256)| {
    //       let filename = std::path::Path::new(url)
    //         .file_name()
    //         .map(|s| s.to_string_lossy().to_string())
    //         .expect("grrrr");

    //       let is_source = filename == "source.json";
    //       DownloadRequest {
    //         filename: filename,
    //         integrity: Integrity::Sha256(sha256.clone()),
    //         kind: match is_source {
    //           true => RequestKind::Source,
    //           _ => RequestKind::Module,
    //         },
    //         url: url.clone(),
    //       }
    //     })
    //     .collect()
  }
}
