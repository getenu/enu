//! A `<canvas>`-like element: a Blitz custom widget that replays a list of
//! 2D drawing commands recorded through the C interface. The commands mirror
//! CanvasRenderingContext2D (paths, fill, stroke, fillText) so the same Nim
//! code can target a real browser canvas.
//!
//! Drawing happens on the CPU with the rest of the page for now. On Godot 4
//! the plan is to give canvases their own GPU texture instead.

use std::cell::RefCell;
use std::rc::Rc;

use anyrender::{Glyph, PaintScene, RenderContext, Scene};
use blitz_dom::Widget;
use blitz_dom::node::ComputedStyles;
use kurbo::{Affine, BezPath, Stroke};
use parley::{
    FontContext, FontFamily, FontWeight, LayoutContext, PositionedLayoutItem, StyleProperty,
};
use peniko::{Color, Fill};

enum Command {
    Fill(BezPath, Color),
    Stroke(BezPath, Color, f64),
    Text { text: String, x: f64, y: f64, size: f32, color: Color, bold: bool },
}

#[derive(Default)]
pub struct CanvasState {
    commands: Vec<Command>,
    path: BezPath,
}

pub struct Text {
    font_cx: FontContext,
    layout_cx: LayoutContext<[u8; 4]>,
}

impl Text {
    pub fn new() -> Self {
        Self { font_cx: FontContext::new(), layout_cx: LayoutContext::new() }
    }

    fn layout(&mut self, text: &str, size: f32, bold: bool) -> parley::Layout<[u8; 4]> {
        let mut builder = self.layout_cx.ranged_builder(&mut self.font_cx, text, 1.0, true);
        builder.push_default(StyleProperty::FontSize(size));
        builder.push_default(StyleProperty::FontFamily(FontFamily::Source("sans-serif".into())));
        if bold {
            builder.push_default(StyleProperty::FontWeight(FontWeight::BOLD));
        }
        let mut layout = builder.build(text);
        layout.break_all_lines(None);
        layout
    }

    pub fn measure(&mut self, text: &str, size: f32, bold: bool) -> f32 {
        self.layout(text, size, bold).width()
    }
}

/// Shared between the widget (which paints) and the C interface (which
/// records). One per canvas element.
pub type Handle = Rc<RefCell<CanvasState>>;

pub struct CanvasWidget {
    pub state: Handle,
    pub text: Rc<RefCell<Text>>,
}

impl Widget for CanvasWidget {
    fn paint(
        &mut self,
        _render_ctx: &mut dyn RenderContext,
        _styles: &ComputedStyles,
        _width: u32,
        _height: u32,
        scale: f64,
    ) -> Scene {
        let mut scene = Scene::new();
        let transform = Affine::scale(scale);
        let state = self.state.borrow();
        let mut text = self.text.borrow_mut();
        for cmd in &state.commands {
            match cmd {
                Command::Fill(path, color) => {
                    scene.fill(Fill::NonZero, transform, *color, None, path);
                }
                Command::Stroke(path, color, width) => {
                    scene.stroke(&Stroke::new(*width), transform, *color, None, path);
                }
                Command::Text { text: s, x, y, size, color, bold } => {
                    // (x, y) is the alphabetic baseline, as in fillText.
                    let layout = text.layout(s, *size, *bold);
                    let Some(line) = layout.lines().next() else { continue };
                    let baseline = line.metrics().baseline as f64;
                    let at = transform * Affine::translate((*x, *y - baseline));
                    for item in line.items() {
                        let PositionedLayoutItem::GlyphRun(run) = item else { continue };
                        let r = run.run();
                        scene.draw_glyphs(
                            r.font(),
                            r.font_size(),
                            true,
                            bytemuck::cast_slice(r.normalized_coords()),
                            kurbo::Vec2::default(),
                            Fill::NonZero,
                            *color,
                            1.0,
                            at,
                            None,
                            run.positioned_glyphs().map(|g| Glyph { id: g.id as _, x: g.x, y: g.y }),
                        );
                    }
                }
            }
        }
        scene
    }
}

fn rgba(c: u32) -> Color {
    Color::from_rgba8((c >> 24) as u8, (c >> 16) as u8, (c >> 8) as u8, c as u8)
}

impl CanvasState {
    pub fn clear(&mut self) {
        self.commands.clear();
        self.path = BezPath::new();
    }
    pub fn begin_path(&mut self) {
        self.path = BezPath::new();
    }
    pub fn move_to(&mut self, x: f64, y: f64) {
        self.path.move_to((x, y));
    }
    pub fn line_to(&mut self, x: f64, y: f64) {
        self.path.line_to((x, y));
    }
    pub fn quad_to(&mut self, cx: f64, cy: f64, x: f64, y: f64) {
        self.path.quad_to((cx, cy), (x, y));
    }
    pub fn cubic_to(&mut self, c1x: f64, c1y: f64, c2x: f64, c2y: f64, x: f64, y: f64) {
        self.path.curve_to((c1x, c1y), (c2x, c2y), (x, y));
    }
    pub fn close_path(&mut self) {
        self.path.close_path();
    }
    pub fn fill(&mut self, color: u32) {
        self.commands.push(Command::Fill(self.path.clone(), rgba(color)));
    }
    pub fn stroke(&mut self, color: u32, width: f64) {
        self.commands.push(Command::Stroke(self.path.clone(), rgba(color), width));
    }
    pub fn fill_text(&mut self, text: &str, x: f64, y: f64, size: f32, color: u32, bold: bool) {
        self.commands.push(Command::Text { text: text.into(), x, y, size, color: rgba(color), bold });
    }
}
