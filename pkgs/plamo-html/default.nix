# plamo-html: 英語混じりの静的 HTML をローカルの llama-server (PLaMo 3 Translate)
# で日本語化して別ファイルに書き出す CLI。詳細は README.md。
{
  lib,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "plamo-html";
  version = "0.1.0";
  pyproject = true;

  src = lib.cleanSource ./.;

  build-system = [ python3Packages.setuptools ];
  dependencies = [ python3Packages.lxml ];

  nativeCheckInputs = [ python3Packages.pytestCheckHook ];

  pythonImportsCheck = [ "plamo_html" ];

  meta = {
    description = "Translate English-heavy HTML to Japanese via a local PLaMo 3 Translate llama-server";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "plamo-html";
  };
}
