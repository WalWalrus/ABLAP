using Archipelago.MultiClient.Net;
using Archipelago.MultiClient.Net.Enums;
using Archipelago.MultiClient.Net.Helpers;
using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Reflection;
using static System.Environment;

class Program
{
    static ArchipelagoSession? _session;

    static bool EnableLevelComplete;

    static bool EnableGrainAll;
    static bool EnableGrainsanity;
    static int GrainsanityStep = 10;

    static bool EnableFlikAll;
    static bool EnableFlikIndividual;

    static bool EnableEnemy25;
    static bool EnableEnemy50;
    static bool EnableEnemy75;
    static bool EnableEnemy100;

    static readonly object _berryLock = new();
    static readonly object _seedLock = new();

    static FileSystemWatcher? _stateWatcher;
    static readonly ManualResetEvent _exitEvent = new(false);

    static bool _propsInitialized;
    static PropertyInfo? _roomSeedProp;
    static PropertyInfo? _itemsReceivedProp;

    static string DataDir =
        Path.Combine(
            GetFolderPath(SpecialFolder.LocalApplicationData),
            "A_Bugs_Life_Archipelago"
        );

    static string StatePath => Path.Combine(DataDir, "abl_state.txt");
    static string CommandPath => Path.Combine(DataDir, "abl_command.txt");
    static string BerryStatePath => Path.Combine(DataDir, "abl_berries.txt");
    static string SeedStatePath => Path.Combine(DataDir, "abl_seeds.txt");
    static string ConfigPath => Path.Combine(DataDir, "abl_config.txt");
    static string SessionPath => Path.Combine(DataDir, "session.txt");
    static string ItemsProcessedPath => Path.Combine(DataDir, "items_processed.txt");

    static readonly int[,] SeedTiers = new int[256, 5];

    static readonly Dictionary<int, int[]> SeedUpgradeCaps = new()
    {
        { 17, new int[]{1, 2, 0, 4, 0} },
        { 1,  new int[]{4, 3, 3, 0, 0} },
        { 3,  new int[]{1, 2, 0, 4, 0} },
        { 2,  new int[]{1, 0, 0, 4, 0} },
        { 6,  new int[]{3, 2, 0, 0, 0} },
        { 10, new int[]{2, 4, 3, 0, 0} },
        { 11, new int[]{1, 0, 4, 0, 2} },
        { 4,  new int[]{1, 4, 1, 4, 2} },
        { 5,  new int[]{2, 2, 4, 4, 0} },
        { 14, new int[]{1, 0, 0, 0, 0} },
        { 7,  new int[]{4, 2, 3, 2, 0} },
        { 12, new int[]{4, 4, 0, 0, 0} },
        { 13, new int[]{1, 3, 0, 4, 0} },
        { 9,  new int[]{2, 4, 4, 0, 3} },
        { 8,  new int[]{1, 0, 0, 0, 0} },
        { 15, new int[]{2, 0, 3, 0, 0} },
    };

    static readonly int[] _berryTiers = new int[256];

    static readonly HashSet<int> BerryProgressionDisabledLevels = new()
    {
        17, // Training
        3,  // Tunnels
        2,  // Council Chamber
        4, // City Entrance
        5, // City Square
        13, // Battle Arena
        9, // Ant Hill Part 2
    };
    static string ReadLineWithDefault(string defaultText)
    {
        var buffer = new List<char>(defaultText);
        Console.Write(defaultText);

        while (true)
        {
            var key = Console.ReadKey(intercept: true);

            switch (key.Key)
            {
                case ConsoleKey.Enter:
                    Console.WriteLine();
                    return new string(buffer.ToArray());

                case ConsoleKey.Backspace:
                    if (buffer.Count > 0)
                    {
                        buffer.RemoveAt(buffer.Count - 1);
                        Console.Write("\b \b"); // erase character visually
                    }
                    break;

                default:
                    if (!char.IsControl(key.KeyChar))
                    {
                        buffer.Add(key.KeyChar);
                        Console.Write(key.KeyChar);
                    }
                    break;
            }
        }
    }

    static void Main(string[] args)
    {
        const string gameName = "A Bug's Life";

        Console.WriteLine("A Bug's Life AP Client v0.1.0");
        Console.WriteLine("This Archipelago Client is compatible only with the NTSC-U release for A Bug's Life (North American PS1 version)");
        Console.WriteLine();

        Directory.CreateDirectory(DataDir);

        string serverAddress = "";
        string slotName = "";
        string password = "";

        while (true)
        {
            Console.Write("Server address (e.g. archipelago.gg:38281): ");
            string serverInput = ReadLineWithDefault("archipelago.gg:").Trim();

            if (!TryNormalizeServerAddress(serverInput, out serverAddress, out string serverError))
            {
                Console.WriteLine(serverError);
                Console.WriteLine();
                continue;
            }

            Console.Write("Slot name: ");
            slotName = (Console.ReadLine() ?? "").Trim();

            if (string.IsNullOrWhiteSpace(slotName))
            {
                Console.WriteLine("Slot name is required.");
                Console.WriteLine();
                continue;
            }

            Console.Write("Password (optional): ");
            password = Console.ReadLine() ?? "";

            _session = ArchipelagoSessionFactory.CreateSession(serverAddress);
            _session.Items.ItemReceived += OnItemReceived;

            var result = _session.TryConnectAndLogin(
                game: gameName,
                name: slotName,
                itemsHandlingFlags: ItemsHandlingFlags.AllItems,
                tags: new[] { "AP" },
                password: string.IsNullOrWhiteSpace(password) ? null : password,
                requestSlotData: true
            );

            if (!result.Successful)
            {
                Console.WriteLine("Login failed. Double-check the server address, slot name, and password.");
                Console.WriteLine();
                continue;
            }

            Console.WriteLine("Connected.");
            Console.WriteLine();

            string seedName = TryGetRoomSeedName(_session) ?? serverAddress;
            string sessionKey = $"{seedName}|{slotName}|{serverAddress}";

            ResetLocalStateIfSessionChanged(sessionKey);
            ReadSlotDataAndWriteConfig(result);

            LoadBerryState();
            LoadSeedState();

            ProcessReceivedItemBacklog();

            Console.WriteLine("Client running. Press Ctrl+C to exit.");

            InitializeReflectionProps(_session);
            SetupStateWatcher();

            Console.CancelKeyPress += (s, e) =>
            {
                Console.WriteLine("Exiting...");
                e.Cancel = true;
                _exitEvent.Set();
            };

            _exitEvent.WaitOne();
            _stateWatcher?.Dispose();
            return;
        }
    }

    static bool TryNormalizeServerAddress(string input, out string normalized, out string error)
    {
        normalized = "";
        error = "";

        if (string.IsNullOrWhiteSpace(input))
        {
            error = "Server address is required.";
            return false;
        }

        string candidate = input.Trim();

        if (!candidate.Contains(':'))
            candidate = $"archipelago.gg:{candidate}";

        if (candidate.EndsWith(":", StringComparison.Ordinal))
        {
            error = "Please include a port number (e.g. archipelago.gg:38281).";
            return false;
        }

        string host;
        string portText;

        if (candidate.StartsWith("[", StringComparison.Ordinal))
        {
            int close = candidate.IndexOf(']');
            if (close <= 0 || close + 2 > candidate.Length || candidate[close + 1] != ':')
            {
                error = "Invalid server format. Use host:port (e.g. archipelago.gg:38281).";
                return false;
            }
            host = candidate.Substring(0, close + 1);
            portText = candidate.Substring(close + 2);
        }
        else
        {
            int lastColon = candidate.LastIndexOf(':');
            if (lastColon <= 0 || lastColon == candidate.Length - 1)
            {
                error = "Invalid server format. Use host:port (e.g. archipelago.gg:38281).";
                return false;
            }
            host = candidate.Substring(0, lastColon);
            portText = candidate.Substring(lastColon + 1);
        }

        if (string.IsNullOrWhiteSpace(host))
        {
            error = "Server host is required (e.g. archipelago.gg:38281).";
            return false;
        }

        if (!int.TryParse(portText, out int port) || port < 1 || port > 65535)
        {
            error = "Invalid port. Please enter a number between 1 and 65535 (e.g. archipelago.gg:38281).";
            return false;
        }

        normalized = $"{host}:{port}";
        return true;
    }

    static void ResetLocalStateIfSessionChanged(string sessionKey)
    {
        string previousKey = "";
        try
        {
            if (File.Exists(SessionPath))
                previousKey = File.ReadAllText(SessionPath);
        }
        catch { }

        if (previousKey == sessionKey)
            return;

        Console.WriteLine("[AP] New session detected; resetting local state.");

        SafeDelete(ConfigPath);
        SafeDelete(SeedStatePath);
        SafeDelete(BerryStatePath);
        SafeDelete(StatePath);
        SafeDelete(CommandPath);
        SafeDelete(ItemsProcessedPath);

        Array.Clear(_berryTiers, 0, _berryTiers.Length);
        for (int i = 0; i < SeedTiers.GetLength(0); i++)
            for (int j = 0; j < SeedTiers.GetLength(1); j++)
                SeedTiers[i, j] = 0;

        try { File.WriteAllText(SessionPath, sessionKey); } catch { }
    }

    static void SafeDelete(string path)
    {
        try
        {
            if (File.Exists(path))
                File.Delete(path);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[AP] Warning: failed to delete {path}: {ex.Message}");
        }
    }

    static string? TryGetRoomSeedName(ArchipelagoSession session)
    {
        try
        {
            var roomState = session.RoomState;
            if (roomState == null) return null;
            // Ensure reflection properties are initialised once.
            if (!_propsInitialized)
                InitializeReflectionProps(session);

            var valObj = _roomSeedProp?.GetValue(roomState);
            var val = valObj?.ToString();
            if (!string.IsNullOrWhiteSpace(val))
                return val;
        }
        catch { }

        return null;
    }

    static void ReadSlotDataAndWriteConfig(object loginResult)
    {
        try
        {
            var slotDataObj = loginResult.GetType().GetProperty("SlotData")?.GetValue(loginResult);
            var slotData = slotDataObj as System.Collections.IDictionary;

            if (slotData == null)
            {
                Console.WriteLine("[AP] Warning: SlotData missing; sanity options default OFF.");
                WriteLuaConfigFile();
                return;
            }

            int GetInt(string key, int def = 0)
            {
                try
                {
                    if (!slotData.Contains(key)) return def;
                    var v = slotData[key];
                    if (v == null) return def;
                    if (v is int i) return i;
                    if (v is long l) return (int)l;
                    if (v is short s) return s;
                    if (v is byte b) return b;
                    if (v is bool bo) return bo ? 1 : 0;
                    if (int.TryParse(v.ToString(), out var p)) return p;
                }
                catch { }
                return def;
            }

            EnableLevelComplete = GetInt("enable_level_complete", 1) != 0;
            EnableGrainAll = GetInt("enable_grain_all", 0) != 0;
            EnableFlikAll = GetInt("enable_flik_all", 0) != 0;
            EnableFlikIndividual = GetInt("enable_flik_individual", 0) != 0;

            EnableGrainsanity = GetInt("enable_grainsanity", 0) != 0;
            GrainsanityStep = Math.Clamp(GetInt("grainsanity_step", 10), 1, 50);

            EnableEnemy25 = GetInt("enable_enemy_25", 0) != 0;
            EnableEnemy50 = GetInt("enable_enemy_50", 0) != 0;
            EnableEnemy75 = GetInt("enable_enemy_75", 0) != 0;
            EnableEnemy100 = GetInt("enable_enemy_100", 0) != 0;

            WriteLuaConfigFile();
        }
        catch (Exception ex)
        {
            Console.WriteLine("[AP] Warning: failed to read SlotData: " + ex.Message);
            WriteLuaConfigFile();
        }
    }

    static void WriteLuaConfigFile()
    {
        try
        {
            Directory.CreateDirectory(DataDir);

            var lines = new List<string>
            {
                $"enable_level_complete={(EnableLevelComplete ? 1 : 0)}",

                $"enable_flik_individual={(EnableFlikIndividual ? 1 : 0)}",
                $"enable_flik_all={(EnableFlikAll ? 1 : 0)}",

                $"enable_grain_all={(EnableGrainAll ? 1 : 0)}",
                $"enable_grainsanity={(EnableGrainsanity ? 1 : 0)}",
                $"grainsanity_step={Math.Clamp(GrainsanityStep, 1, 50)}",

                $"enable_enemy_25={(EnableEnemy25 ? 1 : 0)}",
                $"enable_enemy_50={(EnableEnemy50 ? 1 : 0)}",
                $"enable_enemy_75={(EnableEnemy75 ? 1 : 0)}",
                $"enable_enemy_100={(EnableEnemy100 ? 1 : 0)}",
            };
            File.WriteAllLines(ConfigPath, lines);
        }
        catch (Exception ex)
        {
            Console.WriteLine("[AP] Warning: failed to write abl_config.txt: " + ex.Message);
        }
    }

    static void LoadBerryState()
    {
        Array.Clear(_berryTiers, 0, _berryTiers.Length);

        if (!File.Exists(BerryStatePath))
            return;

        try
        {
            foreach (var line in File.ReadAllLines(BerryStatePath))
            {
                var parts = line.Trim().Split(' ');
                if (parts.Length == 3 && parts[0] == "LEVEL" &&
                    int.TryParse(parts[1], out var idx) &&
                    int.TryParse(parts[2], out var tier))
                {
                    if (idx >= 0 && idx < _berryTiers.Length)
                        _berryTiers[idx] = Math.Clamp(tier, 0, 4);
                }
            }
        }
        catch (IOException ex)
        {
            Console.WriteLine("[AP] Failed to load berry state: " + ex.Message);
        }
    }

    static void SaveBerryState()
    {
        try
        {
            var lines = new List<string>();
            for (int i = 0; i < _berryTiers.Length; i++)
            {
                if (_berryTiers[i] > 0)
                    lines.Add($"LEVEL {i} {_berryTiers[i]}");
            }
            File.WriteAllLines(BerryStatePath, lines);
        }
        catch (IOException ex)
        {
            Console.WriteLine("[AP] Failed to save berry state: " + ex.Message);
        }
    }

    static void LoadSeedState()
    {
        for (int i = 0; i < SeedTiers.GetLength(0); i++)
            for (int j = 0; j < SeedTiers.GetLength(1); j++)
                SeedTiers[i, j] = 0;

        if (!File.Exists(SeedStatePath))
            return;

        try
        {
            foreach (var line in File.ReadAllLines(SeedStatePath))
            {
                var parts = line.Trim().Split(' ');
                if (parts.Length == 7 && parts[0] == "LEVEL" &&
                    int.TryParse(parts[1], out var idx))
                {
                    if (idx < 0 || idx >= 256) continue;

                    for (int c = 0; c < 5; c++)
                    {
                        if (int.TryParse(parts[2 + c], out var tier))
                            SeedTiers[idx, c] = Math.Max(0, tier);
                    }
                }
            }
        }
        catch (IOException ex)
        {
            Console.WriteLine("[AP] Failed to load seed state: " + ex.Message);
        }
    }

    static void SaveSeedState()
    {
        try
        {
            var lines = new List<string>();

            for (int i = 0; i < 256; i++)
            {
                bool any = false;
                for (int c = 0; c < 5; c++)
                    if (SeedTiers[i, c] > 0) any = true;

                if (!any) continue;

                lines.Add($"LEVEL {i} {SeedTiers[i, 0]} {SeedTiers[i, 1]} {SeedTiers[i, 2]} {SeedTiers[i, 3]} {SeedTiers[i, 4]}");
            }

            File.WriteAllLines(SeedStatePath, lines);
        }
        catch (IOException ex)
        {
            Console.WriteLine("[AP] Failed to save seed state: " + ex.Message);
        }
    }
    static void OnItemReceived(ReceivedItemsHelper helper)
    {
        var info = helper.PeekItem();
        HandleItem(info.ItemId, info.ItemName ?? $"Item #{info.ItemId}");
        helper.DequeueItem();

        UpdateItemsProcessedCountFromSession();
    }

    static void ProcessReceivedItemBacklog()
    {
        if (_session == null) return;

        var list = GetReceivedItemsList(_session);
        if (list == null)
        {
            Console.WriteLine("[AP] Warning: could not access received item list (library API mismatch).");
            return;
        }

        int processed = ReadInt(ItemsProcessedPath, 0);
        int count = list.Count;

        if (processed < 0) processed = 0;
        if (processed > count) processed = count;

        if (processed == count)
            return;

        Console.WriteLine($"[AP] Processing received-item backlog: {processed} -> {count}");

        for (int i = processed; i < count; i++)
        {
            var itemObj = list[i];
            if (itemObj == null) continue;

            long id = TryGetLongProperty(itemObj, "ItemId");
            string name = TryGetStringProperty(itemObj, "ItemName") ?? $"Item #{id}";
            HandleItem(id, name);
        }

        try { File.WriteAllText(ItemsProcessedPath, count.ToString()); } catch { }
    }

    static void UpdateItemsProcessedCountFromSession()
    {
        if (_session == null) return;

        var list = GetReceivedItemsList(_session);
        if (list == null) return;

        try { File.WriteAllText(ItemsProcessedPath, list.Count.ToString()); } catch { }
    }

    static IList? GetReceivedItemsList(ArchipelagoSession session)
    {
        try
        {
            var items = session.Items;
            if (items == null) return null;
            // Ensure reflection properties are initialised once.
            if (!_propsInitialized)
                InitializeReflectionProps(session);

            object? val = _itemsReceivedProp?.GetValue(items);
            return val as IList;
        }
        catch
        {
            return null;
        }
    }

    static void InitializeReflectionProps(ArchipelagoSession? session)
    {
        if (_propsInitialized || session == null)
            return;
        try
        {
            var room = session.RoomState;
            if (room != null)
            {
                var type = room.GetType();
                _roomSeedProp = type.GetProperty("Seed");
            }
            var items = session.Items;
            if (items != null)
            {
                var t = items.GetType();
                _itemsReceivedProp = t.GetProperty("AllItemsReceived") ??
                    t.GetProperty("ReceivedItems") ??
                    t.GetProperty("ItemsReceived");
            }
        }
        catch
        {
        }
        _propsInitialized = true;
    }

    static void SetupStateWatcher()
    {
        try
        {
            Directory.CreateDirectory(DataDir);
            var fileName = Path.GetFileName(StatePath);
            _stateWatcher = new FileSystemWatcher(DataDir, fileName)
            {
                NotifyFilter = NotifyFilters.LastWrite,
                EnableRaisingEvents = true
            };
            _stateWatcher.Changed += (s, e) =>
            {
                try
                {
                    ProcessStateFile();
                }
                catch (Exception ex)
                {
                    Console.WriteLine("[AP] State watcher error: " + ex.Message);
                }
            };
        }
        catch (Exception ex)
        {
            Console.WriteLine("[AP] Warning: failed to set up file watcher: " + ex.Message);
        }
    }

    static long TryGetLongProperty(object obj, string propName)
    {
        try
        {
            var p = obj.GetType().GetProperty(propName);
            var v = p?.GetValue(obj);
            if (v is long l) return l;
            if (v is int i) return i;
            if (v is short s) return s;
            if (v is uint ui) return ui;
            if (v is ulong ul) return (long)ul;
            if (v != null && long.TryParse(v.ToString(), out var parsed)) return parsed;
        }
        catch { }
        return 0;
    }

    static string? TryGetStringProperty(object obj, string propName)
    {
        try
        {
            var p = obj.GetType().GetProperty(propName);
            return p?.GetValue(obj)?.ToString();
        }
        catch { return null; }
    }

    static int ReadInt(string path, int fallback)
    {
        try
        {
            if (!File.Exists(path)) return fallback;
            var s = File.ReadAllText(path).Trim();
            if (int.TryParse(s, out var v)) return v;
        }
        catch { }
        return fallback;
    }

    static void HandleItem(long id, string name)
    {
        Console.WriteLine($"[AP] Received item: {name} (ID {id})");

        if (id == 210)
        {
            try
            {
                using var writer = new StreamWriter(CommandPath, append: true);
                writer.WriteLine("LIFE +1");
            }
            catch (IOException ex)
            {
                Console.WriteLine("[AP] Failed to queue extra life: " + ex.Message);
            }
            Console.WriteLine("[AP] Queued extra life");
            return;
        }

        if (id == 211)
        {
            try
            {
                using var writer = new StreamWriter(CommandPath, append: true);
                writer.WriteLine("HEALTH +1");
            }
            catch (IOException ex)
            {
                Console.WriteLine("[AP] Failed to queue health upgrade: " + ex.Message);
            }
            Console.WriteLine("[AP] Queued health upgrade");
            return;
        }

        if (id >= 300 && id < 400)
        {
            int levelIndex = (int)(id - 300);
            if (levelIndex < 0 || levelIndex >= _berryTiers.Length) return;

            if (BerryProgressionDisabledLevels.Contains(levelIndex))
            {
                Console.WriteLine($"[AP] Ignoring berry upgrade for level {levelIndex} (disabled: purple seeds grant berries / no gold berry)");
                return;
            }

            lock (_berryLock)
            {
                int current = _berryTiers[levelIndex];
                if (current < 4)
                {
                    int newTier = current + 1;
                    _berryTiers[levelIndex] = newTier;
                    SaveBerryState();
                    Console.WriteLine($"[AP] Upgraded berry for level {levelIndex} to tier {newTier}");
                }
                else
                {
                    Console.WriteLine($"[AP] Berry tier already max for level {levelIndex}");
                }
            }

            return;
        }

        if (id >= 400 && id < 900)
        {
            HandleSeedUpgrade(id);
            return;
        }
    }

    static void HandleSeedUpgrade(long itemId)
    {
        int colourIndex;
        int levelIndex;

        if (itemId >= 400 && itemId < 500) { colourIndex = 0; levelIndex = (int)(itemId - 400); }
        else if (itemId >= 500 && itemId < 600) { colourIndex = 1; levelIndex = (int)(itemId - 500); }
        else if (itemId >= 600 && itemId < 700) { colourIndex = 2; levelIndex = (int)(itemId - 600); }
        else if (itemId >= 700 && itemId < 800) { colourIndex = 3; levelIndex = (int)(itemId - 700); }
        else if (itemId >= 800 && itemId < 900) { colourIndex = 4; levelIndex = (int)(itemId - 800); }
        else return;

        if (!SeedUpgradeCaps.TryGetValue(levelIndex, out var caps))
            return;

        var cap = caps[colourIndex];
        if (cap <= 0)
            return;

        lock (_seedLock)
        {
            int current = SeedTiers[levelIndex, colourIndex];
            if (current < cap)
            {
                int next = current + 1;
                SeedTiers[levelIndex, colourIndex] = next;
                SaveSeedState();
                Console.WriteLine($"[AP] Seed upgrade: level {levelIndex}, colour {colourIndex}, now {next}");
            }
            else
            {
                Console.WriteLine($"[AP] Seed upgrade already max: level {levelIndex}, colour {colourIndex}, cap {cap}");
            }
        }
    }

    static void ProcessStateFile()
    {
        if (_session == null)
            return;

        if (!File.Exists(StatePath))
            return;

        string[] lines;
        try
        {
            lines = File.ReadAllLines(StatePath);
        }
        catch (IOException)
        {
            return;
        }

        if (lines.Length == 0)
            return;

        try { File.WriteAllText(StatePath, string.Empty); } catch { }

        foreach (var raw in lines)
        {
            var line = raw.Trim();
            if (string.IsNullOrEmpty(line)) continue;

            var parts = line.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 3 || parts[0] != "CHECK") continue;

            if (!int.TryParse(parts[^1], out var levelIndex)) continue;

            int locationId = -1;

            string checkToken = parts[1];

            if (checkToken.Equals("LEVEL_COMPLETE", StringComparison.OrdinalIgnoreCase) && !EnableLevelComplete) continue;

            if (checkToken.Equals("GRAIN", StringComparison.OrdinalIgnoreCase) && !EnableGrainAll) continue;
            if (checkToken.StartsWith("GRAIN", StringComparison.OrdinalIgnoreCase) && checkToken.Length > 5 && !EnableGrainsanity) continue;

            if (checkToken.StartsWith("ENEMIES", StringComparison.OrdinalIgnoreCase) && checkToken.Length > 7)
            {
                if (checkToken.EndsWith("25", StringComparison.OrdinalIgnoreCase) && !EnableEnemy25) continue;
                if (checkToken.EndsWith("50", StringComparison.OrdinalIgnoreCase) && !EnableEnemy50) continue;
                if (checkToken.EndsWith("75", StringComparison.OrdinalIgnoreCase) && !EnableEnemy75) continue;
                if (checkToken.EndsWith("100", StringComparison.OrdinalIgnoreCase) && !EnableEnemy100) continue;
            }

            if (checkToken.Equals("FLIK_ALL", StringComparison.OrdinalIgnoreCase) && !EnableFlikAll) continue;
            if (checkToken.StartsWith("FLIK_", StringComparison.OrdinalIgnoreCase) && checkToken.Length == 6 && !EnableFlikIndividual) continue;

            if (checkToken.StartsWith("GRAIN", StringComparison.OrdinalIgnoreCase))
            {
                int grainAmount = 0;
                int parsedLevelIndex = levelIndex;

                if (checkToken.Length > 5 && int.TryParse(checkToken.Substring(5), out grainAmount))
                {
                }
                else if (parts.Length >= 4 && int.TryParse(parts[2], out grainAmount) && int.TryParse(parts[3], out parsedLevelIndex))
                {
                    levelIndex = parsedLevelIndex;
                }

                if (grainAmount > 0)
                {
                    locationId = 2000 + (levelIndex * 100) + grainAmount;
                }
                else
                {
                    locationId = (1000 + levelIndex * 10) + 5;
                }
            }
            else if (checkToken.StartsWith("ENEMIES", StringComparison.OrdinalIgnoreCase))
            {
                int pct = 0;
                int parsedLevelIndex = levelIndex;

                if (checkToken.Length > 7 && int.TryParse(checkToken.Substring(7), out pct))
                {
                }
                else if (parts.Length >= 4 && int.TryParse(parts[2], out pct) && int.TryParse(parts[3], out parsedLevelIndex))
                {
                    levelIndex = parsedLevelIndex;
                }

                int tier = pct / 25;
                locationId = 3000 + (levelIndex * 10) + tier;
            }
            else
            {
                int baseId = 1000 + levelIndex * 10;
                int offset = checkToken switch
                {
                    "FLIK_F" => 0,
                    "FLIK_L" => 1,
                    "FLIK_I" => 2,
                    "FLIK_K" => 3,
                    "FLIK_ALL" => 4,
                    "LEVEL_COMPLETE" => 7,
                    _ => -1
                };

                if (offset >= 0)
                    locationId = baseId + offset;
            }

            if (locationId < 0) continue;
            Console.WriteLine($"[AP] Completing location {locationId} from {line}");

            try
            {
                _session.Locations.CompleteLocationChecks(locationId);
            }
            catch (Exception ex)
            {
                Console.WriteLine("[AP] Failed to complete location: " + ex.Message);
            }
        }
    }
}