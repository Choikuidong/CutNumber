using static CutNumber.Localization;
using System.IO;

namespace CutNumber;

public sealed record FrameFile(string Path) {
    public string Name => System.IO.Path.GetFileName(Path);
    public DateTime Created => File.GetCreationTimeUtc(Path);
    public DateTime Modified => File.GetLastWriteTimeUtc(Path);
}

public static class FileOperations {
    public static readonly HashSet<string> ImageExtensions = new(StringComparer.OrdinalIgnoreCase) {
        ".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp", ".gif", ".heic", ".heif", ".webp"
    };

    public static List<FrameFile> Sort(IEnumerable<FrameFile> files, int order) {
        var snapshots = files.Select(f => (File: f, Date: order % 2 == 0 ? f.Created : f.Modified));
        return (order < 2 ? snapshots.OrderBy(f => f.Date) : snapshots.OrderByDescending(f => f.Date))
            .ThenBy(f => f.File.Path, StringComparer.OrdinalIgnoreCase).Select(f => f.File).ToList();
    }

    public static List<FrameFile> Collect(IEnumerable<string> inputs, bool recursive, int order) {
        var result = new List<FrameFile>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string input in inputs) {
            var attributes = File.GetAttributes(input);
            if ((attributes & FileAttributes.ReparsePoint) != 0) continue;
            IEnumerable<FrameFile> candidates;
            if (Directory.Exists(input)) {
                var options = new EnumerationOptions {
                    RecurseSubdirectories = recursive, IgnoreInaccessible = false,
                    AttributesToSkip = FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReparsePoint
                };
                candidates = Sort(Directory.EnumerateFiles(input, "*", options)
                    .Where(p => ImageExtensions.Contains(Path.GetExtension(p)))
                    .Select(p => new FrameFile(Path.GetFullPath(p))), order);
            } else {
                candidates = ImageExtensions.Contains(Path.GetExtension(input))
                    ? new[] { new FrameFile(Path.GetFullPath(input)) } : Array.Empty<FrameFile>();
            }
            foreach (var file in candidates) if (seen.Add(file.Path)) result.Add(file);
        }
        return result;
    }

    public static List<string> Names(IReadOnlyList<FrameFile> files, int start, int digits, string prefix) {
        if (files.Count == 0) throw new IOException(T("addFirst"));
        if (start < 0 || start > 999_999_999 - files.Count) throw new IOException(T("invalidStart"));
        if (prefix.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 || prefix.Contains('\n') || prefix.Contains('\r'))
            throw new IOException(T("invalidPrefix"));
        if (files.Select(f => Path.GetExtension(f.Path).ToLowerInvariant()).Distinct().Count() != 1)
            throw new IOException(T("sameExtension"));
        return files.Select((f, i) => prefix + (start + i).ToString("D" + digits) + Path.GetExtension(f.Path).ToLowerInvariant()).ToList();
    }

    public static List<string> Run(IReadOnlyList<FrameFile> files, IReadOnlyList<string> names, string? destination, bool rename) {
        if (files.Count == 0 || files.Count != names.Count) throw new IOException(T("invalidFiles"));
        var targets = files.Select((f, i) => Path.Combine(destination ?? Path.GetDirectoryName(f.Path)!, names[i])).ToList();
        var sources = files.Select(f => f.Path).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (targets.Distinct(StringComparer.OrdinalIgnoreCase).Count() != files.Count) throw new IOException(T("duplicate"));
        foreach (var (file, target) in files.Zip(targets)) {
            if (!File.Exists(file.Path)) throw new IOException((T("readError") + "\n") + file.Path);
            if (Directory.Exists(target) || File.Exists(target) && !(rename && sources.Contains(target)))
                throw new IOException((T("collision") + "\n") + target);
        }
        if (!rename) {
            var copied = new List<string>();
            string? partial = null;
            try {
                foreach (var (file, target) in files.Zip(targets)) {
                    partial = Path.Combine(Path.GetDirectoryName(target)!, ".cutnumber-" + Guid.NewGuid() + ".tmp");
                    File.Copy(file.Path, partial, false);
                    File.Move(partial, target, false);
                    partial = null;
                    copied.Add(target);
                }
            } catch (Exception failure) {
                var remaining = new List<string>();
                if (partial != null) {
                    try { if (File.Exists(partial)) File.Delete(partial); } catch { remaining.Add(partial); }
                }
                foreach (string path in copied) {
                    try { File.Delete(path); } catch { remaining.Add(path); }
                }
                throw new IOException(failure.Message + (remaining.Count == 0 ? ("\n" + T("copiedCleanup")) : ("\n" + T("cleanupNeeded") + "\n") + string.Join("\n", remaining)), failure);
            }
            return targets;
        }
        var staged = files.Select(f => Path.Combine(Path.GetDirectoryName(f.Path)!, ".cutnumber-" + Guid.NewGuid() + ".tmp")).ToArray();
        int stagedCount = 0, completed = 0;
        try {
            for (int i = 0; i < files.Count; i++) { File.Move(files[i].Path, staged[i]); stagedCount++; }
            for (int i = 0; i < files.Count; i++) { File.Move(staged[i], targets[i]); completed++; }
        } catch (Exception failure) {
            var recovery = new List<string>();
            for (int i = completed - 1; i >= 0; i--) {
                try { File.Move(targets[i], staged[i]); }
                catch { recovery.Add(targets[i] + " → " + files[i].Path); }
            }
            for (int i = 0; i < stagedCount; i++) if (File.Exists(staged[i])) {
                try { File.Move(staged[i], files[i].Path); }
                catch { recovery.Add(staged[i] + " → " + files[i].Path); }
            }
            throw new IOException(failure.Message + (recovery.Count == 0 ? ("\n" + T("restored")) : ("\n" + T("recoveryNeeded") + "\n") + string.Join("\n", recovery)), failure);
        }
        return targets;
    }
}
