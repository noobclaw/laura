import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Third-party notices shown on the licence page.
void registerLicences() {
  LicenseRegistry.addLicense(() async* {
    // Display face bundled with the app (SIL OFL 1.1).
    yield LicenseEntryWithLineBreaks(const ['Martian Mono'],
        await rootBundle.loadString('assets/fonts/MartianMono-OFL.txt'));
    // Junction limiting and the gmin/source stepping ladder in the solver
    // follow SpiceSharp (MIT).
    yield const LicenseEntryWithLineBreaks(['SpiceSharp'], _spiceSharpMit);
  });
}

const String _spiceSharpMit = '''MIT License

Copyright (c) 2017 svenboulanger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';
