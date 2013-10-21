//
//  VT100ScreenTest.m
//  iTerm
//
//  Created by George Nachman on 10/16/13.
//
//

#import "iTermTests.h"
#import "VT100ScreenTest.h"
#import "VT100Screen.h"
#import "DVR.h"
#import "DVRDecoder.h"

@implementation VT100ScreenTest {
    VT100Terminal *terminal_;
    int startX_, endX_, startY_, endY_;
    int needsRedraw_;
    int sizeDidChange_;
    BOOL cursorVisible_;
    int triggers_;
}

- (void)setup {
    terminal_ = [[[VT100Terminal alloc] init] autorelease];
    startX_ = endX_ = startY_ = endY_ = -1;
    needsRedraw_ = 0;
    sizeDidChange_ = 0;
    cursorVisible_ = YES;
    triggers_ = 0;
}

- (VT100Screen *)screen {
    return [[[VT100Screen alloc] initWithTerminal:terminal_] autorelease];
}

- (void)testInit {
    VT100Screen *screen = [self screen];

    // Make sure the screen is initialized to a positive size with the cursor at the origin
    assert([screen width] > 0);
    assert([screen height] > 0);
    assert(screen.maxScrollbackLines > 0);
    assert([screen cursorX] == 1);
    assert([screen cursorY] == 1);

    // Make sure it's empty.
    for (int i = 0; i < [screen height] - 1; i++) {
        NSString* s;
        s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         [screen width]);
        assert([s length] == 0);
    }

    // Append some stuff to it to make sure we can retreive it.
    for (int i = 0; i < [screen height] - 1; i++) {
        [screen terminalAppendString:[NSString stringWithFormat:@"Line %d", i] isAscii:YES];
        [screen terminalLineFeed];
        [screen terminalCarriageReturn];
    }
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"Line 0"]);
    assert([screen numberOfLines] == [screen height]);

    // Make sure it has a functioning line buffer.
    [screen terminalLineFeed];
    assert([screen numberOfLines] == [screen height] + 1);
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"Line 1"]);

    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"Line 0"]);

    // Make sure the DVR is there and works.
    [screen saveToDvr];
    DVRDecoder *decoder = [screen.dvr getDecoder];
    [decoder seek:0];
    screen_char_t *frame = (screen_char_t *)[decoder decodedFrame];

    s = ScreenCharArrayToStringDebug(frame,
                                     [screen width]);
    assert([s isEqualToString:@"Line 1"]);
    [self assertInitialTabStopsAreSetInScreen:screen];
}

- (void)assertInitialTabStopsAreSetInScreen:(VT100Screen *)screen {
    // Make sure tab stops are set up properly.
    [screen terminalCarriageReturn];
    int expected = 9;
    while (expected < [screen width]) {
        [screen terminalAppendTabAtCursor];
        assert([screen cursorX] == expected);
        assert([screen cursorY] == [screen height]);
        expected += 8;
    }
}

- (void)testDestructivelySetScreenWidthHeight {
    VT100Screen *screen = [self screen];
    [screen terminalShowTestPattern];
    // Make sure it's full.
    for (int i = 0; i < [screen height] - 1; i++) {
        NSString* s;
        s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         [screen width]);
        assert([s length] == [screen width]);
    }

    int w = [screen width] + 1;
    int h = [screen height] + 1;
    [screen destructivelySetScreenWidth:w height:h];
    assert([screen width] == w);
    assert([screen height] == h);

    // Make sure it's empty.
    for (int i = 0; i < [screen height] - 1; i++) {
        NSString* s;
        s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                         [screen width]);
        assert([s length] == 0);
    }

    // Make sure it is as large as it claims to be
    [screen terminalMoveCursorToX:1 y:1];
    char letters[] = "123456";
    int n = 6;
    NSMutableString *expected = [NSMutableString string];
    for (int i = 0; i < w; i++) {
        NSString *toAppend = [NSString stringWithFormat:@"%c", letters[i % n]];
        [expected appendString:toAppend];
        [screen appendStringAtCursor:toAppend ascii:YES];
    }
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtScreenIndex:0],
                                     [screen width]);
    assert([s isEqualToString:expected]);
}

- (VT100Screen *)screenWithWidth:(int)width height:(int)height {
    VT100Screen *screen = [self screen];
    [screen destructivelySetScreenWidth:width height:height];
    return screen;
}

- (void)appendLines:(NSArray *)lines toScreen:(VT100Screen *)screen {
    for (NSString *line in lines) {
        [screen appendStringAtCursor:line ascii:YES];
        [screen terminalCarriageReturn];
        [screen terminalLineFeed];
    }
}
// abcde+
// fgh..!
// ijkl.!
// .....!
// Cursor at first col of last row.
- (VT100Screen *)fiveByFourScreenWithThreeLinesOneWrapped {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"....."]);
    return screen;
}

// abcdefgh
//
// ijkl.!
// mnopq+
// rst..!
// .....!
// Cursor at first col of last row

- (VT100Screen *)fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrst"] toScreen:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl.\n"
            @"mnopq\n"
            @"rst..\n"
            @"....."]);
    return screen;
}

- (void)showAltAndUppercase:(VT100Screen *)screen {
    [screen terminalShowAltBuffer];
    for (int y = 0; y < screen.height; y++) {
        screen_char_t *line = [screen getLineAtScreenIndex:y];
        for (int x = 0; x < screen.width; x++) {
            unichar c = line[x].code;
            if (isalpha(c)) {
                c -= 'a' - 'A';
            }
            line[x].code = c;
        }
    }
}

- (BOOL)screenHasView {
    return YES;
}

- (int)screenSelectionStartX {
    return startX_;
}

- (int)screenSelectionEndX {
    return endX_;
}

- (int)screenSelectionStartY {
    return startY_;
}

- (int)screenSelectionEndY {
    return endY_;
}

- (void)screenSetSelectionFromX:(int)startX
                          fromY:(int)startY
                            toX:(int)endX
                            toY:(int)endY {
    startX_ = startX;
    startY_ = startY;
    endX_ = endX;
    endY_ = endY;
}

- (void)screenRemoveSelection {
    startX_ = startY_ = endX_ = endY_ = -1;
}

- (void)screenNeedsRedraw {
    needsRedraw_++;
}

- (void)screenSizeDidChange {
    sizeDidChange_++;
}

- (BOOL)screenShouldAppendToScrollbackWithStatusBar {
    return YES;
}

- (void)screenTriggerableChangeDidOccur {
    ++triggers_;
}

- (void)screenSetCursorVisible:(BOOL)visible {
    cursorVisible_ = visible;
}

- (NSString *)selectedStringInScreen:(VT100Screen *)screen {
    if (startX_ < 0 ||
        startY_ < 0 ||
        endX_ < 0 ||
        endY_ < 0) {
        return nil;
    }
    NSMutableString *s = [NSMutableString string];
    int sx = startX_;
    for (int y = startY_; y <= endY_; y++) {
        screen_char_t *line = [screen getLineAtIndex:y];
        int x;
        int ex = y == endY_ ? endX_ : [screen width];
        for (x = sx; x < ex; x++) {
            if (line[x].code) {
                [s appendString:ScreenCharArrayToStringDebug(line + x, 1)];
            }
        }
        if ((y == endY_ &&
             endX_ == [screen width] &&
             line[x - 1].code == 0 &&
             line[x].code == EOL_HARD) ||  // Last line of selection gets a newline iff there's a null char at the end
            (y < endY_ && x == [screen width] && line[x].code == EOL_HARD)) {  // No null required for other lines
            [s appendString:@"\n"];
        }
        sx = 0;
    }
    return s;
}

- (void)testResizeWidthHeight {
    VT100Screen *screen;

    // No change = no-op
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:5 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in primary - shrinks, but everything still fits on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:4 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcd\n"
            @"efgh\n"
            @"ijkl\n"
            @"...."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in primary - grows, but line buffer is empty
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:9 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefgh.\n"
            @"ijkl.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);

    // Try growing vertically only
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:5 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in primary - grows, pulling lines out of line buffer
    screen = [self fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer];
    [screen resizeWidth:6 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"gh....\n"
            @"ijkl..\n"
            @"mnopqr\n"
            @"st....\n"
            @"......"]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 5);

    // Starting in primary, it shrinks, pushing some of primary into linebuffer
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    NSString* s;
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"abc"]);

    // Same tests as above, but in alt screen. -----------------------------------------------------
    // No change = no-op
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:5 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDE\n"
            @"FGH..\n"
            @"IJKL.\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in alt - shrinks, but everything still fits on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:4 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCD\n"
            @"EFGH\n"
            @"IJKL\n"
            @"...."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"abcd\n"
            @"efgh\n"
            @"ijkl\n"
            @"...."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in alt - grows, but line buffer is empty
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:9 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDEFGH.\n"
            @"IJKL.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefgh.\n"
            @"ijkl.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);

    // Try growing vertically only
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:5 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDE\n"
            @"FGH..\n"
            @"IJKL.\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijkl.\n"
            @".....\n"
            @"....."]);

    // Starting in alt - grows, but we don't pull anything out of the line buffer.
    screen = [self fiveByFourScreenWithFourLinesOneWrappedAndOneInLineBuffer];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:6 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"IJKL..\n"
            @"MNOPQR\n"
            @"ST....\n"
            @"......\n"
            @"......"]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl..\n"
            @"mnopqr\n"
            @"st....\n"
            @"......\n"
            @"......"]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 4);

    // Starting in alt, it shrinks, pushing some of primary into linebuffer
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"abc"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:1],
                                     [screen width]);
    assert([s isEqualToString:@"def"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:2],
                                     [screen width]);
    assert([s isEqualToString:@"gh"]);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:3],
                                     [screen width]);
    assert([s isEqualToString:@"ijk"]);

    // Starting in primary with selection, it shrinks, but selection stays on screen
    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "jk"
    startX_ = 1;
    startY_ = 2;
    endX_ = 3;
    endY_ = 2;
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"jk"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in primary with selection, it shrinks, selection is pushed off top completely
    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "abcd"
    startX_ = 0;
    startY_ = 0;
    endX_ = 4;
    endY_ = 0;
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcd"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in primary with selection, it shrinks, selection is pushed off top partially
    // abcde+
    // fgh..!
    // ijkl.!
    // .....!
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "gh\ij"
    startX_ = 1;
    startY_ = 1;
    endX_ = 2;
    endY_ = 2;
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"gh\nij"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in primary with selection, it grows
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "gh\ij"
    startX_ = 1;
    startY_ = 1;
    endX_ = 2;
    endY_ = 2;
    [screen resizeWidth:9 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"abcdefgh.\n"
            @"ijkl.....\n"
            @".........\n"
            @"........."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"gh\nij"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen shrinks but selection stays on screen
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\ij"
    startX_ = 1;
    startY_ = 1;
    endX_ = 2;
    endY_ = 2;
    [screen resizeWidth:4 height:4];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCD\n"
            @"EFGH\n"
            @"IJKL\n"
            @"...."]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and selection is pushed off the top partially
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\nij"
    startX_ = 1;
    startY_ = 1;
    endX_ = 2;
    endY_ = 2;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"IJ"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and selection is pushed off the top completely
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "abc"
    startX_ = 0;
    startY_ = 0;
    endX_ = 3;
    endY_ = 0;
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert([self selectedStringInScreen:screen] == nil);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen grows
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self showAltAndUppercase:screen];
    // select "gh\nij"
    startX_ = 1;
    startY_ = 1;
    endX_ = 2;
    endY_ = 2;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    [screen resizeWidth:6 height:5];
    assert([[screen compactLineDump] isEqualToString:
            @"ABCDEF\n"
            @"GH....\n"
            @"IJKL..\n"
            @"......\n"
            @"......"]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"GH\nIJ"]);
    assert(needsRedraw_ > 0);
    assert(sizeDidChange_ > 0);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen grows, pulling lines out of line buffer into
    // primary grid.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // abcde
    // fgh..
    // ijkl.
    // mnopq
    // rst..
    // uvwxy
    // z....
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    assert([[screen compactLineDump] isEqualToString:
            @"MNOPQ\n"
            @"RST..\n"
            @"UVWXY\n"
            @"Z....\n"
            @"....."]);
    // select everything
    // TODO There's a bug when the selection is at the very end (5,6). It is deselected.
    startX_ = 0;
    startY_ = 0;
    endX_ = 1;
    endY_ = 6;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nijkl\nMNOPQRST\nUVWXYZ"]);
    [screen resizeWidth:6 height:6];
    assert([[screen compactLineDump] isEqualToString:
            @"MNOPQR\n"
            @"ST....\n"
            @"UVWXYZ\n"
            @"......\n"
            @"......\n"
            @"......"]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ"]);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl..\n"
            @"mnopqr\n"
            @"st....\n"
            @"uvwxyz\n"
            @"......\n"
            @"......"]);

    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Starting in alt with selection and screen grows, pulling lines out of line buffer into
    // primary grid. Selection goes to very end of screen
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // abcde
    // fgh..
    // ijkl.
    // mnopq
    // rst..
    // uvwxy
    // z....
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    // select everything
    startX_ = 0;
    startY_ = 0;
    endX_ = 5;
    endY_ = 6;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nijkl\nMNOPQRST\nUVWXYZ\n"]);
    [screen resizeWidth:6 height:6];
    ITERM_TEST_KNOWN_BUG([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ\n"],
                         [[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nMNOPQRST\nUVWXYZ"]);

    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // If lines get pushed into line buffer, excess are dropped
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen setMaxScrollbackLines:1];
    [self showAltAndUppercase:screen];
    [screen resizeWidth:3 height:3];
    assert([[screen compactLineDump] isEqualToString:
            @"IJK\n"
            @"L..\n"
            @"..."]);
    assert(screen.cursorX == 1);
    assert(screen.cursorY == 3);
    s = ScreenCharArrayToStringDebug([screen getLineAtIndex:0],
                                     [screen width]);
    assert([s isEqualToString:@"gh"]);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDump] isEqualToString:
            @"ijk\n"
            @"l..\n"
            @"..."]);

    // Scroll regions are reset
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetLeftMargin:1 rightMargin:2];
    [self showAltAndUppercase:screen];
    [screen terminalSetScrollRegionTop:0 bottom:1];
    [screen terminalSetLeftMargin:0 rightMargin:1];
    [screen resizeWidth:3 height:3];
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 3, 3)));

    // Selection ending at line with trailing nulls
    screen = [self fiveByFourScreenWithThreeLinesOneWrapped];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    // select "efgh.."
    startX_ = 4;
    startY_ = 0;
    endX_ = 5;
    endY_ = 1;
    [screen resizeWidth:3 height:3];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"efgh\n"]);
    needsRedraw_ = 0;
    sizeDidChange_ = 0;

    // Selection starting at beginning of line of all nulls
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen terminalLineFeed];
     [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    // .....
    // abcde
    // fgh..
    // ijkl.
    startX_ = 0;
    startY_ = 0;
    endX_ = 1;
    endY_ = 2;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"\nabcdef"]);
    [screen resizeWidth:13 height:4];
    // TODO
    // This is kind of questionable. We strip nulls in -convertCurrentSelectionToWidth..., while it
    // would be better to preserve the selection.
    ITERM_TEST_KNOWN_BUG([[self selectedStringInScreen:screen] isEqualToString:@"\nabcdef"],
                         [[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);

    // In alt screen with selection that begins in history and ends in history just above the visible
    // screen. The screen grows, moving lines from history into the primary screen. The end of the
    // selection has to move back because some of the selected text is no longer around in the alt
    // screen.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcde\n"
            @"fgh..\n"
            @"ijklm\n"
            @"nopqr\n" // top line of screen
            @"st...\n"
            @"uvwxy\n"
            @"z....\n"
            @"....."]);
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 0;
    endX_ = 2;
    endY_ = 2;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefgh\nij"]);
    [screen resizeWidth:6 height:6];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcdef\n"
            @"NOPQRS\n"
            @"T.....\n"
            @"UVWXYZ\n"
            @"......\n"
            @"......\n"
            @"......"]);
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);
    [screen terminalShowPrimaryBuffer];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"abcdef\n"
            @"gh....\n"
            @"ijklmn\n"
            @"opqrst\n"
            @"uvwxyz\n"
            @"......\n"
            @"......"]);

    // In alt screen with selection that begins in history just above the visible screen and ends
    // onscreen. The screen grows, moving lines from history into the primary screen. The start of the
    // selection has to move forward because some of the selected text is no longer around in the alt
    // screen.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 1;
    startY_ = 2;
    endX_ = 2;
    endY_ = 3;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"jklmNO"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"NO"]);

    // In alt screen with selection that begins and ends onscreen. The screen is grown and some history
    // is deleted.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 4;
    endX_ = 2;
    endY_ = 4;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"ST"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"ST"]);

    // In alt screen with selection that begins in history just above the visible screen and ends
    // there too. The screen grows, moving lines from history into the primary screen. The
    // selection is lost because none of its characters still exist.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 2;
    endX_ = 2;
    endY_ = 2;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"ij"]);
    [screen resizeWidth:6 height:6];
    assert([self selectedStringInScreen:screen] == nil);

    // In alt screen with selection that begins in history and ends in history just above the visible
    // screen. The screen grows, moving lines from history into the primary screen. The end of the
    // selection is exactly at the last character before those that are lost.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 0;
    endX_ = 1;
    endY_ = 1;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);

    // End is one before previous test.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 0;
    endX_ = 5;
    endY_ = 0;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcde"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcde"]);

    // End is two after previous test.
    screen = [self screenWithWidth:5 height:5];
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [self appendLines:@[@"abcdefgh", @"ijklmnopqrst", @"uvwxyz"] toScreen:screen];
    [self showAltAndUppercase:screen];
    startX_ = 0;
    startY_ = 0;
    endX_ = 2;
    endY_ = 1;
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdefg"]);
    [screen resizeWidth:6 height:6];
    assert([[self selectedStringInScreen:screen] isEqualToString:@"abcdef"]);
}

- (VT100Screen *)screenFromCompactLines:(NSString *)compactLines {
    NSArray *lines = [compactLines componentsSeparatedByString:@"\n"];
    VT100Screen *screen = [self screenWithWidth:[[lines objectAtIndex:0] length]
                                         height:[lines count]];
    int i = 0;
    for (NSString *line in lines) {
        screen_char_t *s = [screen getLineAtScreenIndex:i++];
        for (int j = 0; j < [line length]; j++) {
            unichar c = [line characterAtIndex:j];;
            if (c == '.') c = 0;
            if (c == '-') c = DWC_RIGHT;
            if (j == [line length] - 1) {
                if (c == '>') {
                    c = DWC_SKIP;
                    s[j+1].code = EOL_DWC;
                } else {
                    s[j+1].code = EOL_HARD;
                }
            }
            s[j].code = c;
        }
    }
    return screen;
}

- (void)testRunByTrimmingNullsFromRun {
    // Basic test
    VT100Screen *screen = [self screenFromCompactLines:
                           @"..1234\n"
                           @"56789a\n"
                           @"bc...."];
    VT100GridRun run = VT100GridRunMake(1, 0, 16);
    VT100GridRun trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.origin.x == 2);
    assert(trimmed.origin.y == 0);
    assert(trimmed.length == 12);

    // Test wrapping nulls around
    screen = [self screenFromCompactLines:
              @"......\n"
              @".12345\n"
              @"67....\n"
              @"......\n"];
    run = VT100GridRunMake(0, 0, 24);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.origin.x == 1);
    assert(trimmed.origin.y == 1);
    assert(trimmed.length == 7);

    // Test all nulls
    screen = [self screenWithWidth:4 height:4];
    run = VT100GridRunMake(0, 0, 4);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.length == 0);

    // Test no nulls
    screen = [self screenFromCompactLines:
              @"1234\n"
              @"5678"];
    run = VT100GridRunMake(1, 0, 6);
    trimmed = [screen runByTrimmingNullsFromRun:run];
    assert(trimmed.origin.x == 1);
    assert(trimmed.origin.y == 0);
    assert(trimmed.length == 6);
}

- (void)testTerminalResetPreservingPrompt {
    // Test with arg=yes
    VT100Screen *screen = [self screenWithWidth:5 height:3];
    cursorVisible_ = NO;
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:1];
    [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:2];
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalResetPreservingPrompt:YES];
    assert([[screen compactLineDump] isEqualToString:
            @"ijkl.\n"
            @".....\n"
            @"....."]);
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"fgh..\n"
            @"ijkl.\n"
            @".....\n"
            @"....."]);

    assert(screen.cursorX == 5);
    assert(screen.cursorY == 1);
    assert(cursorVisible_);
    assert(triggers_ > 0);
    [self assertInitialTabStopsAreSetInScreen:screen];
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 5, 3)));
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);

    // Test with arg=no
    screen = [self screenWithWidth:5 height:3];
    cursorVisible_ = NO;
    screen.delegate = (id<VT100ScreenDelegate>)self;
    [screen setMaxScrollbackLines:1];
    [self appendLines:@[@"abcdefgh", @"ijkl"] toScreen:screen];
    [screen terminalMoveCursorToX:5 y:2];
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalResetPreservingPrompt:NO];
    assert([[screen compactLineDump] isEqualToString:
            @".....\n"
            @".....\n"
            @"....."]);
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"ijkl.\n"
            @".....\n"
            @".....\n"
            @"....."]);

    assert(screen.cursorX == 1);
    assert(screen.cursorY == 1);
    assert(cursorVisible_);
    assert(triggers_ > 0);
    [self assertInitialTabStopsAreSetInScreen:screen];
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 5, 3)));
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
}

- (void)testAllCharacterSetPropertiesHaveDefaultValues {
    VT100Screen *screen = [self screenWithWidth:5 height:3];
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:0 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    // Switch to charset 1
    char shiftOut = 14;
    char shiftIn = 15;
    NSData *data = [NSData dataWithBytes:&shiftOut length:1];
    [terminal_ putStreamData:data];
    assert([terminal_ parseNextToken]);
    [terminal_ executeToken];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);
    [screen terminalSetCharset:1 toLineDrawingMode:YES];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    [screen terminalResetPreservingPrompt:NO];
    assert(![screen allCharacterSetPropertiesHaveDefaultValues]);

    data = [NSData dataWithBytes:&shiftIn length:1];
    [terminal_ putStreamData:data];
    assert([terminal_ parseNextToken]);
    [terminal_ executeToken];
    assert([screen allCharacterSetPropertiesHaveDefaultValues]);
}

- (void)testClearBuffer {
    VT100Screen *screen;
    screen = [self screenWithWidth:5 height:4];
    [screen terminalSetScrollRegionTop:1 bottom:2];
    [screen terminalSetLeftMargin:1 rightMargin:2];
    [screen terminalSetUseColumnScrollRegion:YES];
    [screen terminalSaveCursorAndCharsetFlags];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen clearBuffer];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @".....\n"
            @".....\n"
            @".....\n"
            @"....."]);
    assert(VT100GridRectEquals([[screen currentGrid] scrollRegionRect],
                               VT100GridRectMake(0, 0, 5, 4)));
    assert([[screen currentGrid] savedCursor].x == 0);
    assert([[screen currentGrid] savedCursor].y == 0);

    // Cursor on last nonempty line
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:3];
    [screen clearBuffer];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"wxyz.\n"
            @".....\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 4);
    assert(screen.cursorY == 1);


    // Cursor in middle of content
    screen = [self screenWithWidth:5 height:4];
    [self appendLines:@[@"abcdefgh", @"ijkl", @"mnopqrstuvwxyz"] toScreen:screen];
    [screen terminalMoveCursorToX:4 y:2];
    [screen clearBuffer];
    assert([[screen compactLineDumpWithHistory] isEqualToString:
            @"rstuv\n"
            @".....\n"
            @".....\n"
            @"....."]);
    assert(screen.cursorX == 4);
    assert(screen.cursorY == 1);
}

/*
 METHODS LEFT TO TEST:

 // Clears the screen and scrollback buffer.
 - (void)clearBuffer;

 // Clears the scrollback buffer, leaving screen contents alone.
 - (void)clearScrollbackBuffer;

 // Append a string to the screen at the current cursor position. The terminal's insert and wrap-
 // around modes are respected, the cursor is advanced, the screen may be scrolled, and the line
 // buffer may change.
 - (void)appendStringAtCursor:(NSString *)s ascii:(BOOL)ascii;

 // This is a hacky thing that moves the cursor to the next line, not respecting scroll regions.
 // It's used for the tmux status screen.
 - (void)crlf;

 // Move the cursor down one position, scrolling if needed. Scroll regions are respected.
 - (void)linefeed;

 // Delete characters in the current line at the cursor's position.
 - (void)deleteCharacters:(int)n;

 // Move the line the cursor is on to the top of the screen and clear everything below.
 - (void)clearScreen;

 // Set the cursor position. Respects the terminal's originmode.
 - (void)cursorToX:(int)x Y:(int)y;

 // Sets the primary grid's contents and scrollback history. |history| is an array of NSData
 // containing screen_char_t's. It contains a bizarre workaround for tmux bugs.
 - (void)setHistory:(NSArray *)history;

 // Sets the alt grid's contents. |lines| is NSData with screen_char_t's.
 - (void)setAltScreen:(NSArray *)lines;

 // Load state from tmux. The |state| dictionary has keys from the kStateDictXxx values.
 - (void)setTmuxState:(NSDictionary *)state;

 // Set the colors in the prototype char to all text on screen that matches the regex.
 // See kHighlightXxxColor constants at the top of this file for dict keys, values are NSColor*s.
 - (void)highlightTextMatchingRegex:(NSString *)regex
 colors:(NSDictionary *)colors;

 // Load a frame from a dvr decoder.
 - (void)setFromFrame:(screen_char_t*)s len:(int)len info:(DVRFrameInfo)info;

 // Save the position of the end of the scrollback buffer without the screen appeneded.
 - (void)saveTerminalAbsPos;

 // Restore the saved position into a passed-in find context (see saveFindContextAbsPos and saveTerminalAbsPos).
 - (void)restoreSavedPositionToFindContext:(FindContext *)context;
*/

@end
