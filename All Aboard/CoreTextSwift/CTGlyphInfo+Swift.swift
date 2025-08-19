//
//  CTGlyphInfo+Swift.swift
//  All Aboard
//
//  Created by Gaurav Bhambhani on 8/4/24.
//

import CoreText

extension  CTGlyphInfo {

  /// Gets the glyph name for a glyph info object if that object exists.
  public var glyphName: String? {
    CTGlyphInfoGetGlyphName(self) as String?
  }

  /// Gets the character identifier for a glyph info object.
  public var characterIdentifier: CGFontIndex {
    CTGlyphInfoGetCharacterIdentifier(self)
  }

  /// Gets the character collection for a glyph info object.
  public var characterCollection: CTCharacterCollection {
    CTGlyphInfoGetCharacterCollection(self)
  }



    @available(iOS 13.0, *)
    public var glyph: CGGlyph {
        CTGlyphInfoGetGlyph(self)
    }
  
}
