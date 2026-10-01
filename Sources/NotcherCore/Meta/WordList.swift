import Foundation

/// Word lists for Lexi and Typer. Lexi also accepts any word from the system
/// dictionary (macOS ships /usr/share/dict/words), plus simple plurals and
/// past tenses of known words.
public final class WordList: @unchecked Sendable {
    public static let shared = WordList()

    public let answers: [String]
    public let typingWords: [String]
    private let lock = NSLock()
    private var extra: Set<String>
    private var dictionary: Set<String>?

    public init(dictionaryPath: String? = "/usr/share/dict/words") {
        answers = Self.answerText.split(whereSeparator: \.isWhitespace).map(String.init)
        typingWords = Self.typingText.split(whereSeparator: \.isWhitespace).map(String.init)
        extra = Set(answers).union(Self.extraText.split(whereSeparator: \.isWhitespace).map(String.init))
        self.dictionaryPath = dictionaryPath
    }

    private let dictionaryPath: String?

    /// Lower-case words of 3…5 letters from the system dictionary, loaded on first use.
    private func systemWords() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if let dictionary { return dictionary }
        var words = Set<String>()
        if let path = dictionaryPath, let text = try? String(contentsOfFile: path, encoding: .utf8) {
            for line in text.split(separator: "\n") where line.count >= 3 && line.count <= 5 {
                if line.allSatisfy({ $0.isLetter && $0.isLowercase && $0.isASCII }) { words.insert(String(line)) }
            }
        }
        dictionary = words
        return words
    }

    public func isValid(_ word: String) -> Bool {
        let w = word.lowercased()
        guard w.count == 5, w.allSatisfy({ $0.isLetter && $0.isASCII }) else { return false }
        if extra.contains(w) { return true }
        let system = systemWords()
        if system.contains(w) { return true }
        // Plurals and past tenses: "cards", "boxes", "baked", "acted".
        let known: (String) -> Bool = { system.contains($0) || self.extra.contains($0) }
        if w.hasSuffix("s"), known(String(w.dropLast())) { return true }
        if w.hasSuffix("es"), known(String(w.dropLast(2))) { return true }
        if w.hasSuffix("ed"), known(String(w.dropLast(2))) || known(String(w.dropLast(1))) { return true }
        return false
    }

    static let answerText = """
        about above actor acute adapt admit adopt adult after again agent agree ahead alarm
        album alert alike alive allow alone along alter amber amend among ample angel anger
        angle angry ankle apart apple apply arena argue arise armor array arrow aside asset
        audio audit avoid awake award aware awful bacon badge baker basic basin beach beard
        beast begin being belly below bench berry birth black blade blame blank blast blaze
        bleak blend bless blind blink block blond blood bloom board boast bonus boost booth
        bound brain brake brand brave bread break breed brick bride brief bring brisk broad
        brook broom brown brush build bunch burst buyer cabin cable camel candy canoe cargo
        carry carve catch cause chain chair chalk charm chart chase cheap check cheek cheer
        chess chest chief child chill choir chord civic civil claim clash class clean clear
        clerk click cliff climb clock close cloth cloud coach coast cobra color comet coral
        couch count court cover crack craft crane crash crate crazy cream creek crest crisp
        cross crowd crown crude crumb crush curve cycle daily dairy dance dealt death debut
        decay delay delta dense depth diary dizzy dodge doing donor doubt dough draft drain
        drama drawn dream dress dried drift drill drink drive dwarf eager eagle early earth
        easel eight elbow elder elite email empty enemy enjoy enter entry equal error essay
        event every exact exile exist extra fable faint fairy faith false fancy feast fence
        ferry fever fiber field fifth fifty fight final flame flash fleet flesh float flock
        flood floor flour fluid flute focus force forge forth forty forum found frame fresh
        front frost fruit fully funny gauge ghost giant given glass gleam globe glory glove
        grace grade grain grand grant grape graph grasp grass grave great greed green greet
        grief grill grind groan group grove guard guess guest guide habit happy harsh haste
        heart heavy hedge hello hinge hobby honey honor horse hotel house human humor hurry
        ideal image imply index inner input irony issue ivory jelly jewel joint judge juice
        jumbo kayak knife knock label labor laser later laugh layer learn lemon level light
        limit linen liver local lodge logic loose lover lower loyal lucky lunar lunch magic
        major maker mango maple march match maybe mayor medal media mercy merit metal meter
        midst minor mixer model money month moral motor mount mouse mouth movie music naive
        nerve never night noble noise north novel nurse ocean offer often olive onion opera
        orbit order organ other otter ounce outer owner oxide paint panel panic paper party
        pasta patch pause peace peach pearl pedal penny phase phone photo piano piece pilot
        pitch pixel pizza place plain plane plant plate plaza point polar porch pound power
        press price pride prime print prior prize proof proud prove pulse punch pupil queen
        quest quick quiet quite quota quote radar radio raise rally ranch range rapid ratio
        reach react ready realm rebel refer relax reply rider ridge rifle right rigid risky
        rival river roast robin robot rocky rough round route royal rugby ruler rural salad
        sauce scale scarf scene scent scone scope score scout scrap sense serve seven shade
        shake shall shape share shark sharp sheep sheet shelf shell shift shine shirt shock
        shore short shout sight silly since skill skirt sleep slice slide slope small smart
        smile smoke snack snake solar solid solve sound south space spare spark speak speed
        spell spend spice spine spoon sport spray squad stack staff stage stair stake stamp
        stand start state steam steel steep stick still stock stone stool storm story stove
        straw strip study style sugar suite sunny super sweet swing sword table taste teach
        tempo thank theme there thick thing think third thorn those three throw thumb tiger
        tight timer title toast today token topic total touch tough towel tower toxic trace
        track trade trail train trait treat trend trial tribe trick truck truly trust truth
        tulip tuner twist ultra uncle under union unity until upper upset urban usage usual
        valid value vapor vault venue verse video vigor viral virus visit vital vivid vocal
        voice wagon waste watch water whale wheat wheel where which while white whole width
        witch woman world worry worth wound woven wrist write wrong yacht yield young youth
        zebra
        """

    static let extraText = """
        abbey abort abuse acorn adore aging aisle alien align alley alloy aloft aloud alpha
        altar amaze amuse angst anime annoy apron arbor ardor aroma ashen askew atlas attic
        avert axiom bagel baggy balmy banjo barge baron basil batch bathe baton bayou beefy
        beret bevel bingo birch bison bitty blimp bliss bloat bluff blunt blurb blurt blush
        bogus bossy bowel boxer brace braid brass brawn briar brine brink broth brute buddy
        budge buggy bugle bulge bully bumpy bunny burly bushy butte cacao cadet canal caper
        carol cater cedar chaos chimp chirp choke chunk churn cider cigar cinch claps clasp
        cleat cling cloak clown clump corny cough cramp crank crave crawl creak creep cress
        crimp croak crook crust cubic cumin curly curry cyber daddy dandy decor decoy dents
        deter devil digit diner dingy dirty disco ditch ditto ditty diver dolly donut dowdy
        dozen drape drawl dread drool droop drove drown druid dryer dummy dunce dusty duvet
        eaten ebony eerie elegy elfin elope elude embed ember emcee enact endow ensue envoy
        epoch equip erase erode erupt evade evict evoke exalt excel exert expel extol exult
        faded fanny farce fatal fault feign feral ferny fetch fiery filly filth finch fishy
        flair flake flaky flank flare flask flick flier fling flint flirt floss flown fluff
        fluke flung flush foamy folly foyer frail freak friar frill frisk frizz froth frown
        froze fudge fungi furor fussy fuzzy gamer gassy gaudy gaunt gauze gavel gawky gecko
        geese genie genre gizmo glade gland glare glaze glide glint gloat gloom gloss glyph
        gnome godly golem goofy goose gorge gouge gourd gravy graze grime gripe grits groom
        gross growl grown gruel gruff grunt guava guild guile guilt guise gulch gully gumbo
        gummy gusto gusty hairy handy hardy harem hasty hatch haunt haven havoc hazel heady
        hefty heist helix heron hippo hitch hoard hoist homer horde hound howdy humid hunch
        hunky husky hutch hydra hyena hyper icing igloo inane inept inert infer ingot inlay
        inlet irate itchy jaunt jazzy jerky jetty jiffy jolly joust jumpy junta kebab khaki
        kiosk kitty knack knead kneel knelt koala krill lance lanky lapel lapse larch large
        larva latch lathe leafy leaky leapt lease leash ledge leech lefty legal lemur lever
        libel lilac limbo liner lingo lipid lithe llama lofty loopy lorry lotus louse lousy
        lumpy lurch lusty lyric macaw macho madam mafia magma mamba mangy mania manor marsh
        mason matey mauve maxim mealy meaty melee melon messy midge mimic mince minty minus
        mirth miser misty mocha modem mogul moist molar moldy moose mossy motel motif motto
        mound mourn mousy mucky muddy mulch mummy mural murky mushy musky muted myrrh nacho
        nanny nasal nasty natty naval navel needy neigh nerdy newly nicer niche niece ninja
        ninth nobly nomad notch nudge nutty nylon nymph oaken oasis octet oddly offal ombre
        omega onset opium optic outdo ovary ovoid owing paddy pager palsy pansy papal parka
        parry pasty patio patsy patty pecan penne perch peril perky pesky petal petty phony
        picky piety piggy pinch piney pinky pinto piper pique pithy pivot pixie plaid plank
        plead pleat pluck plumb plume plump plunk plush poesy poker polka polyp pooch poppy
        posse pouch prank prawn preen primo prism privy probe prone prong prose prowl prude
        prune psalm pudgy puffy pulpy pupal puppy puree purse pushy putty pygmy quack quail
        qualm quark quart quash quasi queer quell query quill quilt quirk rabbi rabid racer
        radii rainy rajah ramen raspy raven rayon razor recap recur reedy regal rehab reign
        remix renew repay repel rerun resin retro reuse revel rhino rhyme rinse ripen risen
        rivet roach robed rodeo rogue roomy roost rotor rouge rowdy ruddy rumba rumor runny
        rusty sadly saint salon salsa salty salve sandy sappy sassy satin satyr sauna savor
        savvy scald scalp scaly scamp scant scare scoff scold scoop scorn scour scowl scram
        scrub scuba sedan seize sepia serum setup shack shaft shaky shale shame shank shard
        shawl sheen sheer shiny shire shirk shoal shone shook shrub shrug shuck shunt sigma
        silky silty sinew singe siren sissy sixth sixty skate skier skimp skulk skull skunk
        slack slain slang slant slash slate sleek sleet slept slick slime slimy sling slosh
        sloth slump slung slunk slurp slush smack smash smear smelt smirk smith smock snail
        snare snarl sneak sneer snide sniff snipe snoop snore snort snout snowy snuck snuff
        soapy sober soggy sonic sooth sooty spade spank spasm spawn spear speck spiel spiky
        spill spilt spire spite splat split spoil spoke spoof spook spool spore spout spree
        sprig spunk spurn spurt squat squib stain stale stalk stall stank stare stark stash
        stave stead steed stein stern stiff sting stink stint stoic stoke stole stomp stony
        stood stoop stork stout strap stray strum strut stuck stuff stump stung stunk stunt
        suave sulky sumac surge surly sushi swami swamp swank swarm swash swath swear sweat
        sweep swell swept swift swill swine swirl swoon swoop synod syrup tabby taboo tacit
        tacky taffy taint tally talon tamer tango tangy taper tapir tardy tarot tasty tatty
        taunt tawny teary tease teddy teeth tenor tense tenth tepid terse testy thief thigh
        thong thump thyme tiara tibia tidal tilde timid tipsy tired titan toady toddy topaz
        torch torso totem toxin trawl tread trite troll troop trout trove truce trump tryst
        tubby tumor tunic turbo tutor twang tweak tweed tweet twice twine twirl udder ulcer
        umbra unarm unbox uncut undid undue unfed unfit unify unlit unmet untie unwed unzip
        usher utter vague valet valor valve vegan venom vicar vigil villa vinyl viola viper
        visor vista vodka vogue vomit voter vouch vowel wacky wafer wager waist waltz wanna
        warty weary weave wedge weedy weigh weird welsh whack wharf whiff whine whiny whirl
        whisk widen widow wield wimpy wince winch windy wiper wispy witty woken wooly woozy
        wordy wormy worse worst wrack wrath wreak wreck wrest wring wrung yearn yeast yodel
        yummy zesty zippy
        """

    static let typingText = """
        the be to of and a in that have it for not on with he as
        you do at this but his by from they we say her she or an will
        my one all would there their what so up out if about who get which go
        me when make can like time no just him know take people into year your good
        some could them see other than then now look only come its over think also back
        after use two how our work first well way even new want because any these give
        day most us is was are been has had were said did made find long down
        may part number sound place world help through much before line right too mean old same
        tell boy follow came show around form three small set put end does another large must
        big such turn here why ask went men read need land different home move try kind
        hand picture again change off play spell air away animal house point page letter mother answer
        found study still learn should high every near add food between own below country plant last
        school father keep tree never start city earth eye light thought head under story saw left
        few while along might close something seem next hard open example begin life always those both
        paper together got group often run important until children side feet car mile night walk white
        sea began grow took river four carry state once book hear stop without second later miss
        idea enough eat face watch far real almost let above girl sometimes mountain cut young talk
        soon list song being leave family
        """
}
