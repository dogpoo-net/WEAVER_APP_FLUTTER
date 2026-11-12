import json
import tempfile
import unittest
from pathlib import Path
from optimize_web import optimize

class OptimizeWebTest(unittest.TestCase):
    def test_keeps_chrome_and_safari_fallback_and_removes_unused_renderers(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            config={'builds':[{'compileTarget':'dart2js','renderer':'canvaskit'}]}
            (root/'flutter_bootstrap.js').write_text('_flutter.buildConfig = '+json.dumps(config)+';\npreferWebParagraph: false')
            for name in ['canvaskit.js','canvaskit.wasm','chromium/canvaskit.js','chromium/canvaskit.wasm','canvaskit.js.symbols','skwasm.wasm','wimp.js','webparagraph/canvaskit.wasm']:
                path=root/'canvaskit'/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text('test')
            optimize(root)
            self.assertEqual(sorted(str(p.relative_to(root/'canvaskit')) for p in (root/'canvaskit').rglob('*') if p.is_file()),['canvaskit.js','canvaskit.wasm','chromium/canvaskit.js','chromium/canvaskit.wasm'])
            (root/'flutter_bootstrap.js').write_text('_flutter.buildConfig = '+json.dumps({'builds':[{'compileTarget':'dart2wasm','renderer':'skwasm'}]})+';\npreferWebParagraph: false')
            with self.assertRaises(ValueError): optimize(root)
            self.assertTrue((root/'canvaskit/canvaskit.wasm').exists())

if __name__=='__main__':unittest.main()
