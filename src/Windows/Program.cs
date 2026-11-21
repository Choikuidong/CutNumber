using static CutNumber.Localization;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using Windows.Media.Editing;
using Windows.Media.MediaProperties;
using Windows.Media.Transcoding;
using Windows.Storage;

namespace CutNumber;

public static class Program {
    public const string Version = "1.0.4";
    [STAThread] public static void Main() {
        var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
        app.DispatcherUnhandledException += (_, e) => {
            MessageBox.Show(e.Exception.Message, T("app"), MessageBoxButton.OK, MessageBoxImage.Error);
            e.Handled = true;
        };
        app.Run(new MainWindow());
    }
}

public sealed class FrameRow(FrameFile file) {
    public FrameFile File { get; set; } = file;
    public string Number { get; set; } = "";
    public string Name => File.Name;
    public string Output { get; set; } = "";
}

public sealed class MainWindow : Window {
    static readonly SolidColorBrush BackgroundBrush = Brush("#101319");
    static readonly SolidColorBrush PanelBrush = Brush("#181D25");
    static readonly SolidColorBrush Accent = Brush("#91E0A3");
    static readonly SolidColorBrush Muted = Brush("#98A2B1");
    readonly ObservableCollection<FrameRow> rows = new();
    readonly DataGrid table = new();
    readonly TextBox prefix = new(), start = new() { Text = "1" };
    readonly ComboBox digits = Combo("1", "001", "0001", "00001", "000001");
    readonly ComboBox timeOrder = Combo(T("createdOld"), T("modifiedOld"), T("createdNew"), T("modifiedNew"));
    readonly ComboBox mode = Combo(T("copy"), T("rename"));
    readonly ComboBox fps = Combo("1 FPS", "12 FPS", "24 FPS", "25 FPS", "30 FPS", "60 FPS");
    readonly CheckBox recursive = new() { Content = T("subfolders"), Foreground = Brushes.White, Margin = new Thickness(0, 10, 0, 8) };
    readonly TextBlock count = Text(T("frameCount", 0), 12), duration = Text(T("duration") + " · " + T("seconds", "0.00"), 12);
    readonly TextBlock status = Text(T("ready"), 11);
    readonly Image preview = new() { Stretch = Stretch.Uniform };
    readonly TextBlock previewTitle = Text(T("selectPhoto"), 13);
    readonly TextBlock previewDetail = Text("", 11);
    readonly TextBlock emptyHint = Text(T("emptyNote"), 20);
    readonly ProgressBar progress = new() { Minimum = 0, Maximum = 100, Height = 4, Visibility = Visibility.Collapsed };
    readonly Grid body = new();
    readonly StackPanel toolbar = new() { Orientation = Orientation.Horizontal };
    bool busy;
    int previewGeneration;

    public MainWindow(MainWindow? previous = null) {
        Title = T("app") + " " + Program.Version;
        Width = 1370; Height = 850; MinWidth = 1150; MinHeight = 740;
        Background = BackgroundBrush; Foreground = Brushes.White;
        FontFamily = new FontFamily("Segoe UI, Malgun Gothic"); FontSize = 12;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        var buttonStyle = new Style(typeof(Button));
        buttonStyle.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(12, 8, 12, 8)));
        buttonStyle.Setters.Add(new Setter(Control.MarginProperty, new Thickness(0, 3, 7, 3)));
        buttonStyle.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(Color.FromRgb(38, 46, 55))));
        buttonStyle.Setters.Add(new Setter(Control.ForegroundProperty, Brushes.White));
        buttonStyle.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(0)));
        Resources.Add(typeof(Button), buttonStyle);
        var root = new DockPanel(); Content = root;
        var menu = new Menu { Background = PanelBrush, Foreground = Brushes.White };
        var applicationMenu = new MenuItem { Header = T("app"), Foreground = Brushes.White };
        var about = new MenuItem { Header = T("about"), Foreground = Brushes.Black }; about.Click += (_, _) => ShowAbout();
        var exit = new MenuItem { Header = T("quit"), Foreground = Brushes.Black, InputGestureText = "Alt+F4" }; exit.Click += (_, _) => Close();
        applicationMenu.Items.Add(about); applicationMenu.Items.Add(new Separator()); applicationMenu.Items.Add(exit);
        menu.Items.Add(applicationMenu); DockPanel.SetDock(menu, Dock.Top); root.Children.Add(menu);
        var heading = new DockPanel { Margin = new Thickness(24, 18, 24, 18) };
        DockPanel.SetDock(heading, Dock.Top); root.Children.Add(heading);
        DockPanel.SetDock(toolbar, Dock.Right); heading.Children.Add(toolbar);
        var languageSelector = new ComboBox {
            ItemsSource = Languages, DisplayMemberPath = "Name", SelectedValuePath = "Code",
            SelectedValue = Code, MinWidth = 125, Margin = new Thickness(0, 3, 10, 3),
            Foreground = Brushes.Black, ToolTip = T("language")
        };
        languageSelector.SelectionChanged += (_, _) => {
            if (busy || languageSelector.SelectedValue is not string code || code == Code) return;
            try {
                SetLanguage(code);
                var replacement = new MainWindow(this);
                Application.Current.MainWindow = replacement;
                replacement.Show();
                Close();
            } catch (Exception ex) { languageSelector.SelectedValue = Code; Error(ex); }
        };
        toolbar.Children.Add(languageSelector);
        toolbar.Children.Add(Button(T("paste"), Paste));
        toolbar.Children.Add(Button(T("folder"), AddFolder));
        toolbar.Children.Add(Button(T("add"), AddImages, true));
        var branding = new StackPanel();
        branding.Children.Add(Text(T("app") + "  " + Program.Version, 25, true));
        branding.Children.Add(Text(T("tagline"), 12)); heading.Children.Add(branding);
        var bottom = new DockPanel { Background = PanelBrush, Margin = new Thickness(0, 1, 0, 0) };
        DockPanel.SetDock(bottom, Dock.Bottom); root.Children.Add(bottom);
        status.Margin = new Thickness(20, 10, 20, 10); bottom.Children.Add(status);
        DockPanel.SetDock(progress, Dock.Bottom); root.Children.Add(progress);
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(276) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(298) }); root.Children.Add(body);
        BuildSidebar(); BuildTable(); BuildPreview();
        if (previous != null) {
            prefix.Text = previous.prefix.Text; start.Text = previous.start.Text;
            digits.SelectedIndex = previous.digits.SelectedIndex;
            timeOrder.SelectedIndex = previous.timeOrder.SelectedIndex;
            mode.SelectedIndex = previous.mode.SelectedIndex; fps.SelectedIndex = previous.fps.SelectedIndex;
            recursive.IsChecked = previous.recursive.IsChecked;
            foreach (var row in previous.rows) rows.Add(row);
            foreach (var row in previous.table.SelectedItems.Cast<FrameRow>()) table.SelectedItems.Add(row);
            RefreshNames();
            WindowStartupLocation = WindowStartupLocation.Manual;
            Left = previous.Left; Top = previous.Top;
            Width = previous.RestoreBounds.Width; Height = previous.RestoreBounds.Height;
            WindowState = previous.WindowState;
            Notify(T("savedLanguage"));
        }
        FlowDirection = Code == "ar" ? FlowDirection.RightToLeft : FlowDirection.LeftToRight;
        preview.FlowDirection = FlowDirection.LeftToRight;
        AllowDrop = true;
        DragOver += (_, e) => { e.Effects = !busy && e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None; e.Handled = true; };
        Drop += async (_, e) => { if (!busy && e.Data.GetData(DataFormats.FileDrop) is string[] paths) await Import(paths); };
        PreviewKeyDown += (_, e) => {
            if (busy || Keyboard.Modifiers != ModifierKeys.Control || Keyboard.FocusedElement is TextBox) return;
            if (e.Key == Key.O) { AddImages(); e.Handled = true; }
            if (e.Key == Key.V) { Paste(); e.Handled = true; }
        };
        Closing += (_, e) => { if (busy) { e.Cancel = true; Notify(T("busy")); } };
    }

    void BuildSidebar() {
        var side = new StackPanel { Margin = new Thickness(20) };
        var scroll = new ScrollViewer { Content = side, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Background = PanelBrush };
        body.Children.Add(scroll);
        side.Children.Add(Text("01   " + T("import"), 15, true));
        side.Children.Add(Text(T("folderTime"), 11)); side.Children.Add(timeOrder); side.Children.Add(recursive);
        side.Children.Add(Button(T("applyTime"), SortByTime));
        side.Children.Add(new Separator { Margin = new Thickness(0, 16, 0, 16) });
        side.Children.Add(Text("02   " + T("filenames"), 15, true));
        side.Children.Add(Text(T("prefix"), 11)); side.Children.Add(prefix);
        side.Children.Add(Text(T("start"), 11)); side.Children.Add(start);
        side.Children.Add(Text(T("digits"), 11)); side.Children.Add(digits);
        side.Children.Add(mode); side.Children.Add(Button(T("saveSequence"), SaveSequence));
        side.Children.Add(new Separator { Margin = new Thickness(0, 16, 0, 16) });
        side.Children.Add(Text("03   " + T("video"), 15, true)); side.Children.Add(fps); side.Children.Add(duration);
        side.Children.Add(Button(T("saveVideo"), SaveVideo, true));
        side.Children.Add(Text(T("videoNote"), 10));
        digits.SelectedIndex = 2; fps.SelectedIndex = 2;
        foreach (var box in new[] { prefix, start }) {
            box.Margin = new Thickness(0, 4, 0, 6); box.Padding = new Thickness(7);
            box.TextChanged += (_, _) => RefreshNames();
        }
        digits.SelectionChanged += (_, _) => RefreshNames(); fps.SelectionChanged += (_, _) => RefreshNames();
    }

    void BuildTable() {
        var area = new DockPanel { Margin = new Thickness(20) }; Grid.SetColumn(area, 1); body.Children.Add(area);
        var heading = new DockPanel { Margin = new Thickness(0, 0, 0, 15) };
        DockPanel.SetDock(count, Dock.Right); count.Foreground = Accent; heading.Children.Add(count);
        heading.Children.Add(Text(T("frames"), 20, true)); DockPanel.SetDock(heading, Dock.Top); area.Children.Add(heading);
        var controls = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 10, 0, 0) };
        controls.Children.Add(Button("↑", () => Move(true))); controls.Children.Add(Button("↓", () => Move(false)));
        controls.Children.Add(Button(T("remove"), Remove)); controls.Children.Add(Button(T("nameSort"), SortByName));
        controls.Children.Add(Button(T("reverse"), Reverse)); controls.Children.Add(Button(T("clear"), Clear));
        DockPanel.SetDock(controls, Dock.Bottom); area.Children.Add(controls);
        var note = Text(T("orderHint"), 11);
        note.TextWrapping = TextWrapping.Wrap; note.Margin = new Thickness(0, 10, 0, 0); DockPanel.SetDock(note, Dock.Bottom); area.Children.Add(note);
        var layer = new Grid(); area.Children.Add(layer);
        table.ItemsSource = rows; table.AutoGenerateColumns = false; table.IsReadOnly = true;
        table.CanUserAddRows = false; table.CanUserDeleteRows = false; table.CanUserSortColumns = false;
        table.SelectionMode = DataGridSelectionMode.Extended; table.SelectionUnit = DataGridSelectionUnit.FullRow;
        table.Background = BackgroundBrush; table.Foreground = Brushes.White; table.RowBackground = PanelBrush;
        table.AlternatingRowBackground = Brush("#1D232C"); table.BorderThickness = new Thickness(0);
        table.GridLinesVisibility = DataGridGridLinesVisibility.None; table.HeadersVisibility = DataGridHeadersVisibility.Column;
        table.RowHeight = 36;
        table.Columns.Add(Column(T("number"), "Number", 58));
        table.Columns.Add(Column(T("original"), "Name", 1, true));
        table.Columns.Add(Column(T("output"), "Output", 1, true));
        var headerStyle = new Style(typeof(DataGridColumnHeader));
        headerStyle.Setters.Add(new Setter(Control.BackgroundProperty, PanelBrush));
        headerStyle.Setters.Add(new Setter(Control.ForegroundProperty, Muted));
        headerStyle.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(8, 10, 8, 10)));
        table.ColumnHeaderStyle = headerStyle;
        table.SelectionChanged += async (_, _) => await UpdatePreview();
        layer.Children.Add(table); emptyHint.HorizontalAlignment = HorizontalAlignment.Center;
        emptyHint.VerticalAlignment = VerticalAlignment.Center; emptyHint.TextAlignment = TextAlignment.Center;
        emptyHint.IsHitTestVisible = false; layer.Children.Add(emptyHint);
    }

    void BuildPreview() {
        var area = new DockPanel { Background = PanelBrush, Margin = new Thickness(0) }; Grid.SetColumn(area, 2); body.Children.Add(area);
        var heading = Text(T("preview"), 16, true); heading.Margin = new Thickness(20); DockPanel.SetDock(heading, Dock.Top); area.Children.Add(heading);
        var details = new StackPanel { Margin = new Thickness(20) };
        previewTitle.TextWrapping = TextWrapping.Wrap; previewDetail.TextWrapping = TextWrapping.Wrap;
        details.Children.Add(previewTitle); details.Children.Add(previewDetail);
        DockPanel.SetDock(details, Dock.Bottom); area.Children.Add(details);
        area.Children.Add(new Border { Background = Brushes.Black, Margin = new Thickness(16), Padding = new Thickness(10), CornerRadius = new CornerRadius(10), Child = preview });
    }

    async void AddImages() {
        var dialog = new OpenFileDialog { Title = T("add"), Multiselect = true, Filter = T("images") + "|*.png;*.jpg;*.jpeg;*.tif;*.tiff;*.bmp;*.gif;*.heic;*.heif;*.webp|" + T("allFiles") + "|*.*" };
        if (dialog.ShowDialog(this) == true) await Import(dialog.FileNames);
    }
    async void AddFolder() {
        var dialog = new OpenFolderDialog { Title = T("chooseInput") };
        if (dialog.ShowDialog(this) == true) await Import(new[] { dialog.FolderName });
    }
    async void Paste() {
        try {
            if (!Clipboard.ContainsFileDropList()) { Notify(T("pasteHint")); return; }
            await Import(Clipboard.GetFileDropList().Cast<string>());
        } catch (Exception ex) { Error(ex); }
    }
    async Task Import(IEnumerable<string> paths) {
        if (busy) return;
        var input = paths.ToArray(); int order = timeOrder.SelectedIndex; bool subfolders = recursive.IsChecked == true;
        SetBusy(true); Notify(T("loading"));
        try {
            var imported = await Task.Run(() => FileOperations.Collect(input, subfolders, order));
            var seen = rows.Select(r => r.File.Path).ToHashSet(StringComparer.OrdinalIgnoreCase); int added = 0;
            foreach (var file in imported) if (seen.Add(file.Path)) { rows.Add(new FrameRow(file)); added++; }
            RefreshNames(); Notify((T("added", added, rows.Count)));
            if (table.SelectedItem == null && rows.Count > 0) table.SelectedItem = rows[0];
        } catch (Exception ex) { Error(ex); }
        finally { SetBusy(false); }
    }
    void RefreshNames() {
        List<string>? names = null;
        try { names = FileOperations.Names(rows.Select(r => r.File).ToList(), StartNumber(), Digits(), prefix.Text); } catch { }
        for (int i = 0; i < rows.Count; i++) { rows[i].Number = (i + 1).ToString("D4"); rows[i].Output = names?[i] ?? T("checkSettings"); }
        table.Items.Refresh(); count.Text = T("frameCount", rows.Count);
        emptyHint.Visibility = rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        duration.Text = T("duration") + " · " + T("seconds", ((double)rows.Count / Fps()).ToString("F2"));
    }
    int StartNumber() => int.TryParse(start.Text, out int value) && value >= 0 ? value : throw new IOException(T("invalidStart"));
    int Digits() => new[] { 1, 3, 4, 5, 6 }[Math.Max(0, digits.SelectedIndex)];
    int Fps() => new[] { 1, 12, 24, 25, 30, 60 }[Math.Max(0, fps.SelectedIndex)];
    void Move(bool up) {
        var selected = table.SelectedItems.Cast<FrameRow>().ToHashSet();
        if (up) { for (int i = 1; i < rows.Count; i++) if (selected.Contains(rows[i]) && !selected.Contains(rows[i - 1])) rows.Move(i, i - 1); }
        else { for (int i = rows.Count - 2; i >= 0; i--) if (selected.Contains(rows[i]) && !selected.Contains(rows[i + 1])) rows.Move(i, i + 1); }
        RefreshNames();
    }
    void Remove() { foreach (var row in table.SelectedItems.Cast<FrameRow>().ToArray()) rows.Remove(row); RefreshNames(); }
    void Clear() { rows.Clear(); RefreshNames(); }
    void ReplaceOrder(IEnumerable<FrameRow> ordered) {
        var list = ordered.ToArray(); var selected = table.SelectedItems.Cast<FrameRow>().ToArray();
        rows.Clear(); foreach (var row in list) rows.Add(row);
        foreach (var row in selected) table.SelectedItems.Add(row); RefreshNames();
    }
    void SortByName() => ReplaceOrder(rows.OrderBy(r => r.Name, StringComparer.CurrentCultureIgnoreCase));
    void Reverse() => ReplaceOrder(rows.Reverse());
    void SortByTime() {
        try {
            var byPath = rows.ToDictionary(r => r.File.Path, StringComparer.OrdinalIgnoreCase);
            ReplaceOrder(FileOperations.Sort(rows.Select(r => r.File), timeOrder.SelectedIndex).Select(f => byPath[f.Path]));
        } catch (Exception ex) { Error(ex); }
    }

    async Task UpdatePreview() {
        int generation = ++previewGeneration;
        var selected = table.SelectedItems.Cast<FrameRow>().ToHashSet();
        var row = rows.FirstOrDefault(selected.Contains); preview.Source = null; previewDetail.Text = "";
        if (row == null) { previewTitle.Text = T("selectPhoto"); return; }
        previewTitle.Text = row.Name; previewDetail.Text = T("loading");
        try {
            var image = await Task.Run(() => LoadBitmap(row.File.Path, 1600));
            if (generation != previewGeneration) return;
            preview.Source = image.Image;
            previewDetail.Text = $"{image.Width} × {image.Height} px" + (selected.Count > 1 ? ("\n" + T("selected", selected.Count)) : "");
        } catch (Exception) {
            if (generation == previewGeneration) previewDetail.Text = T("imageError") + "\n" + T("codecNote");
        }
    }

    internal static (BitmapSource Image, int Width, int Height) LoadBitmap(string path, int maximum = 0) {
        using var stream = File.OpenRead(path);
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        var frame = decoder.Frames[0]; int width = frame.PixelWidth, height = frame.PixelHeight;
        int orientation = 1;
        if (frame.Metadata is BitmapMetadata metadata) {
            foreach (string query in new[] { "/app1/ifd/{ushort=274}", "/ifd/{ushort=274}" }) {
                try { if (metadata.GetQuery(query) is ushort value) { orientation = value; break; } } catch { }
            }
        }
        BitmapSource image = frame;
        var transform = new TransformGroup();
        if (orientation is 2 or 5 or 7) transform.Children.Add(new ScaleTransform(-1, 1));
        if (orientation == 4) transform.Children.Add(new ScaleTransform(1, -1));
        double rotation = orientation switch { 3 => 180, 5 or 6 => 90, 7 or 8 => 270, _ => 0 };
        if (rotation != 0) transform.Children.Add(new RotateTransform(rotation));
        if (transform.Children.Count > 0) image = new TransformedBitmap(image, transform);
        width = image.PixelWidth; height = image.PixelHeight;
        if (maximum > 0 && Math.Max(width, height) > maximum) {
            double factor = (double)maximum / Math.Max(width, height);
            image = new TransformedBitmap(image, new ScaleTransform(factor, factor));
        }
        image.Freeze(); return (image, width, height);
    }

    async void SaveSequence() {
        if (busy || rows.Count == 0) return;
        try {
            var files = rows.Select(r => r.File).ToList();
            var names = FileOperations.Names(files, StartNumber(), Digits(), prefix.Text);
            bool rename = mode.SelectedIndex == 1; string? destination = null;
            if (rename) {
                if (MessageBox.Show(this, (T("confirmRename", files.Count)), T("rename"), MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
            } else {
                var folder = new OpenFolderDialog { Title = T("chooseOutput") };
                if (folder.ShowDialog(this) != true) return; destination = folder.FolderName;
            }
            SetBusy(true); Notify(T("working"));
            var result = await Task.Run(() => FileOperations.Run(files, names, destination, rename));
            if (rename) { rows.Clear(); foreach (string path in result) rows.Add(new FrameRow(new FrameFile(path))); RefreshNames(); }
            Notify(T("filesDone", files.Count, rename ? T("rename") : T("copy"))); Reveal(result[0]);
        } catch (Exception ex) { Error(ex); }
        finally { SetBusy(false); }
    }

    async void SaveVideo() {
        if (busy || rows.Count == 0) return;
        var dialog = new SaveFileDialog { Title = T("saveVideo"), Filter = "MP4|*.mp4", FileName = "CutNumber.mp4", DefaultExt = ".mp4" };
        if (dialog.ShowDialog(this) != true) return;
        if (File.Exists(dialog.FileName)) { Error(new IOException(T("collision"))); return; }
        string temporaryDirectory = Path.Combine(Path.GetTempPath(), "CutNumber-" + Guid.NewGuid());
        string temporaryOutput = Path.Combine(Path.GetDirectoryName(dialog.FileName)!, ".cutnumber-" + Guid.NewGuid() + ".mp4");
        SetBusy(true); progress.Visibility = Visibility.Visible; progress.Value = 0;
        try {
            Directory.CreateDirectory(temporaryDirectory);
            var files = rows.Select(r => r.File.Path).ToArray(); int rate = Fps();
            var first = LoadBitmap(files[0], 4096);
            int width = Math.Max(2, (first.Image.PixelWidth + 1) / 2 * 2), height = Math.Max(2, (first.Image.PixelHeight + 1) / 2 * 2);
            var composition = new MediaComposition();
            for (int i = 0; i < files.Length; i++) {
                Notify((T("preparing", i + 1, files.Length)));
                string normalized = Path.Combine(temporaryDirectory, i.ToString("D9") + ".png");
                await Dispatcher.InvokeAsync(() => Normalize(files[i], normalized, width, height), System.Windows.Threading.DispatcherPriority.Background);
                var file = await StorageFile.GetFileFromPathAsync(normalized);
                long startTick = (long)Math.Round((double)i * TimeSpan.TicksPerSecond / rate);
                long endTick = (long)Math.Round((double)(i + 1) * TimeSpan.TicksPerSecond / rate);
                composition.Clips.Add(await MediaClip.CreateFromImageFileAsync(file, TimeSpan.FromTicks(endTick - startTick)));
                progress.Value = 30.0 * (i + 1) / files.Length;
            }
            var folder = await StorageFolder.GetFolderFromPathAsync(Path.GetDirectoryName(temporaryOutput)!);
            var output = await folder.CreateFileAsync(Path.GetFileName(temporaryOutput), CreationCollisionOption.FailIfExists);
            var profile = MediaEncodingProfile.CreateMp4(VideoEncodingQuality.HD1080p);
            profile.Video.Width = (uint)width; profile.Video.Height = (uint)height;
            profile.Video.FrameRate.Numerator = (uint)rate; profile.Video.FrameRate.Denominator = 1;
            profile.Video.Bitrate = (uint)Math.Clamp((long)width * height * rate / 5, 2_000_000, 80_000_000);
            profile.Audio = null;
            Notify(T("encoding"));
            var operation = composition.RenderToFileAsync(output, MediaTrimmingPreference.Precise, profile);
            operation.Progress = (_, percent) => Dispatcher.InvokeAsync(() => progress.Value = 30 + 0.7 * percent);
            var result = await operation;
            if (result != TranscodeFailureReason.None) throw new IOException(T("videoError") + " · " + result + ("\n" + T("mediaPack")));
            File.Move(temporaryOutput, dialog.FileName, false);
            Notify((T("videoDone", files.Length, rate))); Reveal(dialog.FileName);
        } catch (Exception ex) { Error(ex); }
        finally {
            try { if (File.Exists(temporaryOutput)) File.Delete(temporaryOutput); } catch { }
            try { if (Directory.Exists(temporaryDirectory)) Directory.Delete(temporaryDirectory, true); } catch { }
            progress.Visibility = Visibility.Collapsed; SetBusy(false);
        }
    }
    static void Normalize(string source, string destination, int width, int height) {
        var loaded = LoadBitmap(source, 4096).Image;
        double scale = Math.Min((double)width / loaded.PixelWidth, (double)height / loaded.PixelHeight);
        double w = loaded.PixelWidth * scale, h = loaded.PixelHeight * scale;
        var drawing = new DrawingVisual();
        using (var context = drawing.RenderOpen()) {
            context.DrawRectangle(Brushes.Black, null, new Rect(0, 0, width, height));
            context.DrawImage(loaded, new Rect((width - w) / 2, (height - h) / 2, w, h));
        }
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32); bitmap.Render(drawing);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(destination); encoder.Save(stream);
    }
    void ShowAbout() {
        var dialog = new Window {
            Title = T("about"), Width = 540, SizeToContent = SizeToContent.Height,
            ResizeMode = ResizeMode.NoResize, Owner = this,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Background = Brushes.White, Foreground = BackgroundBrush,
            FlowDirection = Code == "ar" ? FlowDirection.RightToLeft : FlowDirection.LeftToRight
        };
        TextBlock AboutText(string value, double size, bool secondary = false, bool bold = false) => new() {
            Text = value, FontSize = size, TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center,
            Foreground = secondary ? Brushes.Gray : BackgroundBrush,
            FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal
        };
        var content = new StackPanel { Margin = new Thickness(32, 24, 32, 30) };
        content.Children.Add(AboutText(T("app"), 30, bold: true));
        var version = AboutText(T("version") + Program.Version, 13, secondary: true);
        version.Margin = new Thickness(0, 10, 0, 0);
        content.Children.Add(version);
        var date = AboutText(T("date"), 11, secondary: true);
        date.Margin = new Thickness(0, 8, 0, 0);
        content.Children.Add(date);
        content.Children.Add(new Separator { Margin = new Thickness(0, 20, 0, 23) });
        var brand = new StackPanel {
            Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center,
            FlowDirection = FlowDirection.LeftToRight
        };
        brand.Children.Add(new Image {
            Source = new BitmapImage(new Uri("pack://application:,,,/AppleCraftSymbol.png")),
            Width = 32, Height = 36, Stretch = Stretch.Uniform, Margin = new Thickness(0, 0, 12, 0)
        });
        brand.Children.Add(AboutText(T("company"), 18, bold: true));
        content.Children.Add(brand);
        var developer = AboutText(T("developer"), 13);
        developer.Margin = new Thickness(0, 20, 0, 0);
        content.Children.Add(developer);
        var homepage = new Hyperlink(new Run("applecraft.kr ↗")) {
            NavigateUri = new Uri("https://applecraft.kr"), Foreground = Brushes.DodgerBlue
        };
        homepage.RequestNavigate += (_, e) => {
            try { Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true }); }
            catch (Exception ex) { Error(ex); }
            e.Handled = true;
        };
        var link = new TextBlock {
            TextAlignment = TextAlignment.Center, FontSize = 13,
            Margin = new Thickness(0, 26, 0, 0), FlowDirection = FlowDirection.LeftToRight
        };
        link.Inlines.Add(homepage);
        content.Children.Add(link);
        var copyright = AboutText("© 2026 Apple Craft. All rights reserved.", 11, secondary: true);
        copyright.Margin = new Thickness(0, 40, 0, 0);
        content.Children.Add(copyright);
        dialog.Content = content;
        dialog.ShowDialog();
    }
    void SetBusy(bool value) { busy = value; body.IsEnabled = !value; toolbar.IsEnabled = !value; }
    void Notify(string message) => status.Text = message;
    void Error(Exception ex) { Notify(T("failed")); MessageBox.Show(this, ex.Message, T("app"), MessageBoxButton.OK, MessageBoxImage.Error); }
    static void Reveal(string path) {
        try { Process.Start(new ProcessStartInfo("explorer.exe", "/select,\"" + path + "\"") { UseShellExecute = true }); } catch { }
    }
    static SolidColorBrush Brush(string color) => new((Color)ColorConverter.ConvertFromString(color));
    static TextBlock Text(string text, double size, bool bold = false) => new() { Text = text, FontSize = size, FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal, Foreground = bold ? Brushes.White : Muted, Margin = new Thickness(0, 5, 0, 6), TextWrapping = TextWrapping.Wrap };
    static ComboBox Combo(params string[] values) => new() { ItemsSource = values, SelectedIndex = 0, Margin = new Thickness(0, 5, 0, 7), Padding = new Thickness(6), Foreground = Brushes.Black, MinHeight = 30 };
    static Button Button(string title, Action action, bool prominent = false) {
        var button = new Button { Content = title };
        if (prominent) { button.Background = Accent; button.Foreground = BackgroundBrush; }
        button.Click += (_, _) => action(); return button;
    }
    static DataGridTextColumn Column(string title, string property, double width, bool star = false) => new() { Header = title, Binding = new Binding(property), Width = new DataGridLength(width, star ? DataGridLengthUnitType.Star : DataGridLengthUnitType.Pixel) };
}
