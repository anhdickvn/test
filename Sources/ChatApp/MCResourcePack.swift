import Foundation
import UIKit
import ZIPFoundation

/// Quản lý resource pack Minecraft 1.12.x.
/// - Tự nhận pack server gửi qua Resource Pack Send.
/// - Cho phép người dùng import .zip thủ công.
/// - Giải nén và tra texture PNG từ assets/minecraft.
/// - Nếu pack không có texture/model phù hợp, UI sẽ fallback về emoji.
@MainActor
final class MCResourcePackStore: ObservableObject {
    static let shared = MCResourcePackStore()

    @Published private(set) var activePackName: String?
    @Published private(set) var activePackURL: URL?

    private var files: [String: URL] = [:]
    private var imageCache: [String: UIImage] = [:]
    private var modelTextureCache: [String: String?] = [:]

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "mc_active_resource_pack"),
           FileManager.default.fileExists(atPath: saved) {
            loadExtractedPack(URL(fileURLWithPath: saved), displayName: URL(fileURLWithPath: saved).lastPathComponent)
        }
    }

    func importPack(from zipURL: URL) async throws {
        let accessed = zipURL.startAccessingSecurityScopedResource()
        defer { if accessed { zipURL.stopAccessingSecurityScopedResource() } }

        let base = try FileManager.default.url(for: .documentDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
            .appendingPathComponent("TexturePacks", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let folder = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: zipURL, to: folder)

        loadExtractedPack(folder, displayName: zipURL.deletingPathExtension().lastPathComponent)
    }

    func installDownloadedPack(zipURL: URL, name: String) throws {
        let base = try FileManager.default.url(for: .documentDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
            .appendingPathComponent("TexturePacks", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let folder = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: zipURL, to: folder)

        loadExtractedPack(folder, displayName: name)
    }

    func clearPack() {
        activePackName = nil
        activePackURL = nil
        files.removeAll()
        imageCache.removeAll()
        modelTextureCache.removeAll()
        UserDefaults.standard.removeObject(forKey: "mc_active_resource_pack")
    }

    func image(for item: MCItemSlot) -> UIImage? {
        image(for: itemId, damage: item.damage)
    }

    func image(for item: MCOpenWindowItem) -> UIImage? {
        image(for: itemId, damage: item.damage)
    }

    private func image(for itemId: Int16, damage: Int16) -> UIImage? {
        guard activePackURL != nil else { return nil }

        let modelNames = mcLegacyItemTextureNames(itemId: itemId, damage: damage)
        for name in modelNames {
            if let modelPath = find("assets/minecraft/models/item/\(name).json") {
                let key = modelPath.path
                let textureRef: String?
                if let cached = modelTextureCache[key] {
                    textureRef = cached
                } else {
                    textureRef = parseLayer0(from: modelPath)
                    modelTextureCache[key] = textureRef
                }
                if let textureRef, let img = imageForTextureReference(textureRef) {
                    return img
                }
            }

            if let img = imageForTextureReference("items/\(name)") ?? imageForTextureReference("blocks/\(name)") {
                return img
            }
        }

        return nil
    }

    private func imageForTextureReference(_ reference: String) -> UIImage? {
        let normalized = reference
            .replacingOccurrences(of: "minecraft:", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let key = normalized.hasSuffix(".png") ? normalized : normalized + ".png"

        if let cached = imageCache[key] { return cached }
        guard let url = find("assets/minecraft/textures/\(key)"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        imageCache[key] = image
        return image
    }

    private func parseLayer0(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let textures = obj["textures"] as? [String: Any],
              let layer0 = textures["layer0"] as? String else {
            return nil
        }
        return layer0
    }

    private func loadExtractedPack(_ folder: URL, displayName: String) {
        var index: [String: URL] = [:]
        if let enumerator = FileManager.default.enumerator(at: folder,
                                                            includingPropertiesForKeys: [.isRegularFileKey],
                                                            options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                let relative = url.path.replacingOccurrences(of: folder.path + "/", with: "")
                    .replacingOccurrences(of: "\\", with: "/")
                    .lowercased()
                index[relative] = url
            }
        }

        // Một số pack được zip với 1 thư mục cha. Index theo suffix để vẫn tìm được assets/.
        var suffixIndex = index
        for (path, url) in index {
            if let range = path.range(of: "assets/minecraft/") {
                suffixIndex[String(path[range.lowerBound...])] = url
            }
        }

        files = suffixIndex
        imageCache.removeAll()
        modelTextureCache.removeAll()
        activePackURL = folder
        activePackName = displayName
        UserDefaults.standard.set(folder.path, forKey: "mc_active_resource_pack")
    }

    private func find(_ relative: String) -> URL? {
        files[relative.lowercased()]
    }
}

/// Tên item legacy phổ biến của Java 1.12.2.
/// Với resource pack custom, model JSON của pack sẽ quyết định texture thực tế.
/// Các ID không có trong bảng sẽ dùng fallback emoji.
func mcLegacyItemTextureNames(itemId: Int16, damage: Int16) -> [String] {
    let map: [Int16: String] = [
        256:"iron_shovel",257:"iron_pickaxe",258:"iron_axe",259:"flint_and_steel",
        260:"apple",261:"bow",262:"arrow",263:"coal",264:"diamond",265:"iron_ingot",266:"gold_ingot",
        267:"iron_sword",268:"wooden_sword",269:"wooden_shovel",270:"wooden_pickaxe",271:"wooden_axe",
        272:"stone_sword",273:"stone_shovel",274:"stone_pickaxe",275:"stone_axe",
        276:"diamond_sword",277:"diamond_shovel",278:"diamond_pickaxe",279:"diamond_axe",
        280:"stick",281:"bowl",282:"mushroom_stew",283:"golden_sword",284:"golden_shovel",
        285:"golden_pickaxe",286:"golden_axe",287:"string",288:"feather",289:"gunpowder",
        290:"wooden_hoe",291:"stone_hoe",292:"iron_hoe",293:"diamond_hoe",294:"golden_hoe",
        295:"wheat_seeds",296:"wheat",297:"bread",298:"leather_helmet",299:"leather_chestplate",
        300:"leather_leggings",301:"leather_boots",302:"chainmail_helmet",303:"chainmail_chestplate",
        304:"chainmail_leggings",305:"chainmail_boots",306:"iron_helmet",307:"iron_chestplate",
        308:"iron_leggings",309:"iron_boots",310:"diamond_helmet",311:"diamond_chestplate",
        312:"diamond_leggings",313:"diamond_boots",314:"golden_helmet",315:"golden_chestplate",
        316:"golden_leggings",317:"golden_boots",318:"flint",319:"porkchop",320:"cooked_porkchop",
        321:"painting",322:"golden_apple",323:"sign",324:"wooden_door",325:"bucket",326:"water_bucket",
        327:"lava_bucket",328:"minecart",329:"saddle",330:"iron_door",331:"redstone",332:"snowball",
        333:"boat",334:"leather",335:"milk_bucket",336:"brick",337:"clay_ball",338:"sugar_cane",
        339:"paper",340:"book",341:"slime_ball",342:"chest_minecart",343:"furnace_minecart",
        344:"egg",345:"compass",346:"fishing_rod",347:"clock",348:"glowstone_dust",
        349:"fish",350:"cooked_fish",351:"dye",352:"bone",353:"sugar",354:"cake",
        355:"bed",356:"repeater",357:"cookie",358:"filled_map",359:"shears",360:"melon",
        361:"pumpkin_seeds",362:"melon_seeds",363:"beef",364:"cooked_beef",365:"chicken",
        366:"cooked_chicken",367:"rotten_flesh",368:"ender_pearl",369:"blaze_rod",
        370:"ghast_tear",371:"gold_nugget",372:"nether_wart",373:"potion",374:"glass_bottle",
        375:"spider_eye",376:"fermented_spider_eye",377:"blaze_powder",378:"magma_cream",
        379:"brewing_stand",380:"cauldron",381:"ender_eye",382:"speckled_melon",383:"spawn_egg",
        384:"experience_bottle",385:"fire_charge",386:"writable_book",387:"written_book",
        388:"emerald",389:"item_frame",390:"flower_pot",391:"carrot",392:"potato",393:"baked_potato",
        394:"poisonous_potato",395:"map",396:"golden_carrot",397:"skull",398:"carrot_on_a_stick",
        399:"nether_star",400:"pumpkin_pie",401:"fireworks",402:"firework_charge",403:"enchanted_book",
        404:"comparator",405:"netherbrick",406:"quartz",407:"tnt_minecart",408:"hopper_minecart",
        409:"prismarine_shard",410:"prismarine_crystals",411:"rabbit",412:"cooked_rabbit",
        413:"rabbit_stew",414:"rabbit_foot",415:"rabbit_hide",416:"armor_stand",417:"iron_horse_armor",
        418:"golden_horse_armor",419:"diamond_horse_armor",420:"lead",421:"name_tag",422:"command_block_minecart",
        423:"mutton",424:"cooked_mutton",425:"banner",426:"end_crystal",427:"spruce_door",
        428:"birch_door",429:"jungle_door",430:"acacia_door",431:"dark_oak_door",
        432:"chorus_fruit",433:"chorus_fruit_popped",434:"beetroot",435:"beetroot_seeds",
        436:"beetroot_soup",437:"dragon_breath",438:"splash_potion",439:"spectral_arrow",
        440:"tipped_arrow",441:"lingering_potion",442:"shield",443:"elytra",444:"spruce_boat",
        445:"birch_boat",446:"jungle_boat",447:"acacia_boat",448:"dark_oak_boat",
        449:"totem_of_undying",450:"shulker_shell",452:"iron_nugget"
    ]
    if let name = map[itemId] { return [name] }

    // Block-items: many 1.12 block IDs use the same basename under textures/blocks.
    let blockNames: [Int16:String] = [
        1:"stone",2:"grass",3:"dirt",4:"cobblestone",5:"planks",6:"sapling",7:"bedrock",
        12:"sand",13:"gravel",14:"gold_ore",15:"iron_ore",16:"coal_ore",17:"log",18:"leaves",
        20:"glass",21:"lapis_ore",22:"lapis_block",23:"dispenser",24:"sandstone",25:"noteblock",
        27:"golden_rail",28:"detector_rail",29:"sticky_piston",30:"web",31:"tallgrass",32:"deadbush",
        33:"piston",35:"wool",37:"yellow_flower",38:"red_flower",39:"brown_mushroom",40:"red_mushroom",
        41:"gold_block",42:"iron_block",43:"double_stone_slab",44:"stone_slab",45:"brick_block",
        46:"tnt",47:"bookshelf",48:"mossy_cobblestone",49:"obsidian",50:"torch",52:"mob_spawner",
        53:"oak_stairs",54:"chest",56:"diamond_ore",57:"diamond_block",58:"crafting_table",
        61:"furnace",65:"ladder",67:"stone_stairs",73:"redstone_ore",74:"lit_redstone_ore",
        79:"ice",80:"snow",81:"cactus",82:"clay",84:"jukebox",86:"pumpkin",87:"netherrack",
        88:"soul_sand",89:"glowstone",91:"lit_pumpkin",92:"cake",98:"stonebrick",99:"brown_mushroom_block",
        100:"red_mushroom_block",103:"melon_block",110:"mycelium",112:"nether_brick",121:"end_stone",
        129:"emerald_ore",133:"emerald_block",137:"command_block",138:"beacon",139:"cobblestone_wall",
        152:"redstone_block",155:"quartz_block",159:"stained_hardened_clay",160:"stained_glass_pane",
        162:"log2",163:"acacia_stairs",164:"dark_oak_stairs",168:"prismarine",169:"sea_lantern",
        170:"hay_block",171:"carpet",172:"hardened_clay",173:"coal_block",174:"packed_ice",
        175:"double_plant",256:"iron_shovel"
    ]
    if let name = blockNames[itemId] { return [name] }
    return []
}
