"""Static reference data: names, cities, catalog definitions, channels, campaigns.

Everything here is fictional (company, brands, creators, affiliate networks).
"""

# --------------------------------------------------------------------------
# Countries and people
# --------------------------------------------------------------------------
# country code -> (share of customers, English name used by GA4)
COUNTRIES = {
    "BE": (0.45, "Belgium"),
    "NL": (0.30, "Netherlands"),
    "FR": (0.12, "France"),
    "DE": (0.09, "Germany"),
    "LU": (0.04, "Luxembourg"),
}

# Name pools per "name culture"
FIRST_NAMES = {
    "flemish": ["Lotte", "Emma", "Noor", "Lien", "Marie", "Fien", "Ella", "Hanne", "Sofie", "Lore",
                "Jana", "Elise", "Nina", "Febe", "Charlotte", "Anke", "Ine", "Katrien", "Eva", "Laura",
                "Wout", "Arne", "Jens", "Pieter", "Thomas", "Ruben", "Seppe", "Lars", "Bram", "Jonas",
                "Stijn", "Tibo", "Robbe", "Lucas", "Milan", "Wannes", "Koen", "Joris", "Dries", "Maarten"],
    "walloon": ["Camille", "Manon", "Léa", "Chloé", "Juliette", "Pauline", "Margaux", "Lucie", "Elodie", "Céline",
                "Amélie", "Inès", "Clara", "Mathilde", "Zoé", "Louis", "Hugo", "Nathan", "Maxime", "Antoine",
                "Julien", "Quentin", "Simon", "Arnaud", "Romain", "Florian", "Cédric", "Thibault", "Adrien", "Gauthier"],
    "dutch": ["Sanne", "Femke", "Anouk", "Lisa", "Iris", "Fleur", "Romy", "Lotte", "Mirthe", "Tessa",
              "Eline", "Maud", "Daan", "Sem", "Bas", "Jesse", "Thijs", "Niels", "Stefan", "Ruud",
              "Joost", "Teun", "Luuk", "Gijs", "Tim", "Martijn", "Jeroen", "Mark", "Sven", "Koen"],
    "french": ["Camille", "Léa", "Manon", "Chloé", "Emma", "Jade", "Louise", "Alice", "Anaïs", "Claire",
               "Elsa", "Marine", "Océane", "Lucas", "Théo", "Hugo", "Mathis", "Baptiste", "Clément", "Victor",
               "Alexandre", "Benjamin", "Guillaume", "Nicolas", "Pierre", "Rémi", "Valentin", "Yann", "Bastien", "Loïc"],
    "german": ["Anna", "Lena", "Laura", "Julia", "Lea", "Sophie", "Hannah", "Katharina", "Johanna", "Miriam",
               "Franziska", "Carla", "Jonas", "Lukas", "Leon", "Felix", "Tobias", "Florian", "Jan", "Moritz",
               "Sebastian", "Niklas", "Philipp", "Matthias", "Stefan", "Jakob", "Benedikt", "Fabian", "Tim", "Paul"],
}
LAST_NAMES = {
    "flemish": ["Peeters", "Janssens", "Maes", "Jacobs", "Mertens", "Willems", "Claes", "Goossens", "Wouters", "De Smet",
                "Vermeulen", "Van Damme", "De Backer", "Hermans", "Michiels", "Van den Broeck", "Verhoeven", "De Clercq",
                "Aerts", "Smets", "Lambrechts", "Coppens", "Van de Velde", "Verstraete", "Desmet", "Dhondt",
                "Vandenberghe", "Declercq", "Van Hecke", "Verbeke", "Cools", "Segers", "Pauwels", "Martens", "Bogaerts"],
    "walloon": ["Dubois", "Lambert", "Dupont", "Martin", "Simon", "Laurent", "Leroy", "Renard", "Collard", "François",
                "Lejeune", "Henrard", "Gilson", "Marchal", "Thiry", "Lemaire", "Leclercq", "Denis", "Mathieu", "Piette",
                "Hubert", "Gérard", "Delvaux", "Noël", "Bodart"],
    "dutch": ["de Jong", "Jansen", "de Vries", "van den Berg", "van Dijk", "Bakker", "Visser", "Smit", "Meijer", "de Boer",
              "Mulder", "de Groot", "Bos", "Vos", "Peters", "Hendriks", "van Leeuwen", "Dekker", "Brouwer", "de Wit",
              "Dijkstra", "Smits", "de Graaf", "van der Meer", "Kok", "Jacobs", "van der Linden", "Vermeer", "Postma", "Kuipers"],
    "french": ["Bernard", "Thomas", "Petit", "Robert", "Richard", "Durand", "Moreau", "Laurent", "Michel", "Garcia",
               "Roux", "Fournier", "Girard", "Bonnet", "Mercier", "Blanc", "Guerin", "Faure", "Rousseau", "Chevalier",
               "Perrin", "Morin", "Lefebvre", "Gauthier", "Clement"],
    "german": ["Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker", "Schulz", "Hoffmann",
               "Koch", "Richter", "Klein", "Wolf", "Schröder", "Neumann", "Schwarz", "Zimmermann", "Braun", "Krüger",
               "Hofmann", "Hartmann", "Lange", "Werner", "Krause"],
}

# country -> list of (name culture, language, probability)
CULTURES = {
    "BE": [("flemish", "nl", 0.62), ("walloon", "fr", 0.36), ("german", "de", 0.02)],
    "NL": [("dutch", "nl", 1.0)],
    "FR": [("french", "fr", 1.0)],
    "DE": [("german", "de", 1.0)],
    "LU": [("walloon", "fr", 0.55), ("german", "de", 0.45)],
}

# country -> list of (postal code, city, weight). Weights roughly follow population/climbing scene.
CITIES = {
    "BE": [("1000", "Brussel", 8), ("1050", "Elsene", 4), ("1030", "Schaarbeek", 3), ("2000", "Antwerpen", 9),
           ("2018", "Antwerpen", 4), ("9000", "Gent", 10), ("3000", "Leuven", 7), ("8000", "Brugge", 4),
           ("3500", "Hasselt", 3), ("2800", "Mechelen", 3), ("8500", "Kortrijk", 2), ("9300", "Aalst", 2),
           ("2300", "Turnhout", 1), ("4000", "Liège", 5), ("5000", "Namur", 4), ("6000", "Charleroi", 2),
           ("1300", "Wavre", 2), ("1348", "Louvain-la-Neuve", 3), ("4700", "Eupen", 1), ("5500", "Dinant", 1)],
    "NL": [("1011", "Amsterdam", 10), ("1053", "Amsterdam", 5), ("3011", "Rotterdam", 7), ("3511", "Utrecht", 8),
           ("2511", "Den Haag", 5), ("5611", "Eindhoven", 4), ("6511", "Nijmegen", 4), ("9711", "Groningen", 4),
           ("6811", "Arnhem", 3), ("2311", "Leiden", 3), ("5011", "Tilburg", 2), ("4811", "Breda", 2),
           ("6211", "Maastricht", 3), ("7511", "Enschede", 2)],
    "FR": [("75011", "Paris", 8), ("75018", "Paris", 4), ("69001", "Lyon", 5), ("59000", "Lille", 6),
           ("38000", "Grenoble", 5), ("77300", "Fontainebleau", 3), ("67000", "Strasbourg", 3), ("31000", "Toulouse", 3),
           ("13001", "Marseille", 3), ("44000", "Nantes", 2), ("35000", "Rennes", 2)],
    "DE": [("10115", "Berlin", 7), ("10997", "Berlin", 3), ("50667", "Köln", 6), ("52062", "Aachen", 5),
           ("80331", "München", 6), ("40213", "Düsseldorf", 4), ("20095", "Hamburg", 4), ("60311", "Frankfurt am Main", 3),
           ("01067", "Dresden", 2), ("79098", "Freiburg im Breisgau", 3)],
    "LU": [("1111", "Luxembourg", 10), ("4001", "Esch-sur-Alzette", 4), ("9001", "Ettelbruck", 2), ("3401", "Dudelange", 2)],
}

# Email domains per country (mixture of global and local providers)
EMAIL_DOMAINS = {
    "BE": [("gmail.com", 45), ("hotmail.com", 14), ("outlook.com", 10), ("telenet.be", 15), ("skynet.be", 5),
           ("proximus.be", 3), ("icloud.com", 8)],
    "NL": [("gmail.com", 45), ("hotmail.com", 14), ("outlook.com", 10), ("ziggo.nl", 10), ("kpnmail.nl", 7),
           ("icloud.com", 10), ("xs4all.nl", 4)],
    "FR": [("gmail.com", 45), ("orange.fr", 15), ("free.fr", 10), ("hotmail.fr", 12), ("laposte.net", 6),
           ("icloud.com", 8), ("outlook.fr", 4)],
    "DE": [("gmail.com", 35), ("web.de", 20), ("gmx.de", 20), ("t-online.de", 10), ("icloud.com", 8),
           ("outlook.de", 7)],
    "LU": [("gmail.com", 45), ("pt.lu", 20), ("hotmail.com", 12), ("icloud.com", 10), ("outlook.com", 13)],
}
TYPO_DOMAINS = {"gmail.com": "gmial.com", "hotmail.com": "hotmial.com", "outlook.com": "outlok.com",
                "telenet.be": "telnet.be", "icloud.com": "icloud.co"}

PAYMENT_METHODS = {
    "BE": [("Bancontact", 55), ("Credit card", 18), ("PayPal", 14), ("Klarna", 8), ("Apple Pay", 5)],
    "NL": [("iDEAL", 62), ("Credit card", 10), ("PayPal", 14), ("Klarna", 9), ("Apple Pay", 5)],
    "FR": [("Credit card", 60), ("PayPal", 25), ("Klarna", 8), ("Apple Pay", 7)],
    "DE": [("PayPal", 40), ("Klarna", 25), ("Credit card", 25), ("Apple Pay", 10)],
    "LU": [("Credit card", 50), ("PayPal", 30), ("Klarna", 10), ("Apple Pay", 10)],
}

# --------------------------------------------------------------------------
# Catalog (fictional brands)
# --------------------------------------------------------------------------
BRANDS = [
    # name, own brand?
    ("Crimpwell", False), ("Granitex", False), ("Slabline", False), ("Dynova", False),
    ("Pinchwick", False), ("Arete Labs", False), ("Mantlo", False), ("Kalkberg Basics", True),
    ("Ledgewood Press", False),
]

# category name, parent, n products, min price, max price, cost ratio (on net price),
# variant type, return rate, weight in first orders, weight in repeat orders, brands
CATEGORIES = [
    ("Climbing shoes", "Footwear", 45, 79, 189, 0.52, "shoe", 0.16, 0.30, 0.11, ["Crimpwell", "Granitex", "Kalkberg Basics"]),
    ("Chalk", "Bouldering", 20, 5, 25, 0.35, "none", 0.01, 0.13, 0.25, ["Pinchwick", "Kalkberg Basics", "Granitex"]),
    ("Chalk bags & buckets", "Bouldering", 25, 14, 45, 0.40, "none", 0.03, 0.08, 0.05, ["Pinchwick", "Mantlo", "Kalkberg Basics"]),
    ("Crash pads", "Bouldering", 15, 129, 399, 0.55, "none", 0.05, 0.05, 0.03, ["Mantlo", "Granitex"]),
    ("Harnesses", "Hardware", 18, 49, 129, 0.50, "harness", 0.08, 0.06, 0.03, ["Dynova", "Granitex"]),
    ("Ropes", "Hardware", 15, 119, 279, 0.55, "rope", 0.03, 0.02, 0.02, ["Dynova"]),
    ("Quickdraws & carabiners", "Hardware", 30, 8, 169, 0.50, "none", 0.02, 0.03, 0.05, ["Granitex", "Dynova"]),
    ("Belay devices", "Hardware", 12, 19, 119, 0.50, "none", 0.02, 0.03, 0.02, ["Granitex", "Dynova"]),
    ("Helmets", "Hardware", 10, 49, 139, 0.50, "helmet", 0.06, 0.02, 0.02, ["Granitex", "Dynova"]),
    ("Clothing", "Apparel", 70, 25, 119, 0.42, "apparel", 0.12, 0.10, 0.12, ["Slabline", "Kalkberg Basics"]),
    ("Training", "Training", 25, 15, 249, 0.50, "none", 0.04, 0.04, 0.07, ["Arete Labs", "Kalkberg Basics"]),
    ("Accessories", "Bouldering", 40, 4, 35, 0.35, "none", 0.01, 0.10, 0.19, ["Pinchwick", "Kalkberg Basics", "Arete Labs"]),
    ("Books & guides", "Other", 15, 19, 45, 0.60, "none", 0.02, 0.02, 0.02, ["Ledgewood Press"]),
    ("Gift cards", "Other", 1, 25, 150, 1.00, "giftcard", 0.00, 0.01, 0.01, ["Kalkberg Basics"]),
]

# Which categories are bought together (row = category of first item)
AFFINITY = {
    "Climbing shoes": {"Chalk": 4, "Chalk bags & buckets": 3, "Accessories": 3, "Clothing": 1},
    "Chalk": {"Accessories": 3, "Chalk bags & buckets": 2, "Clothing": 1, "Training": 1},
    "Chalk bags & buckets": {"Chalk": 5, "Accessories": 2},
    "Crash pads": {"Chalk": 3, "Accessories": 3, "Books & guides": 2, "Chalk bags & buckets": 1},
    "Harnesses": {"Belay devices": 4, "Quickdraws & carabiners": 3, "Helmets": 2, "Chalk bags & buckets": 1},
    "Ropes": {"Quickdraws & carabiners": 4, "Belay devices": 2, "Accessories": 1},
    "Quickdraws & carabiners": {"Ropes": 2, "Belay devices": 2, "Accessories": 1},
    "Belay devices": {"Quickdraws & carabiners": 3, "Harnesses": 1},
    "Helmets": {"Harnesses": 2, "Quickdraws & carabiners": 2},
    "Clothing": {"Clothing": 4, "Accessories": 1, "Chalk": 1},
    "Training": {"Accessories": 3, "Chalk": 2, "Training": 1},
    "Accessories": {"Chalk": 3, "Accessories": 2, "Clothing": 1},
    "Books & guides": {"Crash pads": 1, "Chalk": 2, "Accessories": 1},
    "Gift cards": {"Chalk": 1, "Accessories": 1},
}

MODEL_NAMES = {
    "Climbing shoes": ["Talon", "Vortex", "Ridgeback", "Slipstream", "Hook", "Pivot", "Kestrel", "Raptor", "Nimbus",
                       "Torque", "Feather", "Comet", "Lynx", "Falcon", "Viper"],
    "Chalk": ["Loose Chalk", "Chalk Block", "Chalk Ball", "Liquid Chalk", "Eco Chalk", "Fine Grain Chalk", "Chunky Chalk"],
    "Chalk bags & buckets": ["Chalk Bag", "Chalk Bucket", "Boulder Bucket", "Roll-top Chalk Bag", "Mini Chalk Bag"],
    "Crash pads": ["Crash Pad", "Highball Pad", "Sit-start Pad", "Taco Pad", "Hinge Pad"],
    "Harnesses": ["Sport Harness", "Gym Harness", "Alpine Harness", "Trad Harness"],
    "Ropes": ["9.5 Rope", "9.8 Rope", "10.1 Gym Rope", "9.2 Dry Rope", "8.9 Single Rope"],
    "Quickdraws & carabiners": ["Quickdraw", "Quickdraw 6-pack", "Screwgate Carabiner", "Wiregate Carabiner",
                                "HMS Carabiner", "Quickdraw 12-pack"],
    "Belay devices": ["Tube Belay Device", "Assisted Belay Device", "Guide Plate"],
    "Helmets": ["Climbing Helmet", "Lightweight Helmet"],
    "Clothing": ["Climbing Pants", "Boulder Shorts", "Tee", "Hoodie", "Tank Top", "Leggings", "Beanie", "Jacket"],
    "Training": ["Hangboard", "Pinch Block", "Grip Trainer", "Resistance Bands", "Finger Rings", "Campus Rungs"],
    "Accessories": ["Boulder Brush", "Brush Set", "Finger Tape", "Climbing Balm", "Skin File", "Shoe Deodoriser",
                    "Rope Bag", "Shoe Bag"],
    "Books & guides": ["Bouldering in the Ardennes", "Fontainebleau Circuits", "Train to Send", "The Climber's Body",
                       "Belgian Crags", "Movement on Rock", "Mental Game", "Indoor Bouldering Handbook"],
    "Gift cards": ["Gift Card"],
}
MODEL_SUFFIXES = ["", " Pro", " LV", " II", " Lite", " Plus", " Comp", " X", " Evo"]

SHOE_SIZES = [x / 2 for x in range(72, 93)]           # EU 36 .. 46 in half sizes
APPAREL_SIZES = ["XS", "S", "M", "L", "XL", "XXL"]
HARNESS_SIZES = ["XS", "S", "M", "L", "XL"]
HELMET_SIZES = ["S/M", "M/L"]
ROPE_LENGTHS = [("60 m", 1.00, 0.50), ("70 m", 1.12, 0.35), ("80 m", 1.25, 0.15)]
GIFT_CARD_VALUES = [(25, 0.35), (50, 0.40), (100, 0.20), (150, 0.05)]

# --------------------------------------------------------------------------
# Marketing
# --------------------------------------------------------------------------
# Acquisition channel shares (hidden truth), repeat multiplier, AOV multiplier
ACQUISITION_CHANNELS = {
    "organic_search": (0.23, 1.10, 1.00),
    "paid_search":    (0.21, 1.00, 1.05),
    "paid_social":    (0.17, 0.75, 0.95),
    "direct":         (0.10, 1.20, 1.00),
    "referral":       (0.06, 1.00, 1.00),
    "influencer":     (0.08, 0.70, 0.92),
    "affiliate":      (0.07, 0.65, 0.90),
    "email":          (0.08, 1.30, 1.00),
}

# Fictional creators (influencer marketing)
CREATORS = [
    # handle, platform, code, start, end, monthly fee
    ("lena.sends", "Instagram", "LENA15", "2024-01-15", "2024-12-31", 1500),
    ("crimp_kid", "TikTok", "CRIMP15", "2024-04-01", "2025-09-30", 900),
    ("bloc_brothers", "YouTube", "BLOCBROS", "2024-09-01", "2026-10-31", 2200),
    ("font_freak", "Instagram", "FONT15", "2025-03-01", "2026-06-30", 1200),
    ("slab_sophie", "TikTok", "SOPHIE15", "2025-10-01", "2026-10-31", 800),
]

AFFILIATES = [("climbdeals", "CLIMBDEALS10"), ("outdoorvouchers", None)]
AFFILIATE_COMMISSION = 0.08

REFERRAL_SOURCES = [("reddit.com", 3), ("youtube.com", 3), ("l.instagram.com", 4), ("m.facebook.com", 2),
                    ("bloc-blog.example", 2), ("cragnotes.example", 1), ("gym-partners.example", 2)]

# Google Ads campaigns: name, type, start, end, CTR, CPC
GOOGLE_CAMPAIGNS = [
    ("Search - Brand", "Search", "2023-11-01", "2026-10-31", 0.20, 0.32),
    ("Search - Generic - Climbing Shoes", "Search", "2023-11-01", "2026-10-31", 0.065, 0.95),
    ("Search - Generic - Crash Pads", "Search", "2023-11-01", "2026-10-31", 0.055, 0.80),
    ("Search - Generic - Hardware", "Search", "2024-03-01", "2026-10-31", 0.050, 0.85),
    ("Shopping - All Products", "Shopping", "2023-11-01", "2025-01-31", 0.012, 0.52),
    ("PMax - All Products", "Performance Max", "2025-02-01", "2026-10-31", 0.010, 0.58),
    ("Search - Black Friday 2023", "Search", "2023-11-15", "2023-11-27", 0.080, 1.10),
    ("Search - Black Friday 2024", "Search", "2024-11-18", "2024-12-02", 0.080, 1.15),
    ("Search - Black Friday 2025", "Search", "2025-11-17", "2025-12-01", 0.080, 1.20),
    ("Search - Summer Sale 2024", "Search", "2024-07-01", "2024-07-21", 0.070, 0.90),
    ("Search - Summer Sale 2025", "Search", "2025-07-01", "2025-07-21", 0.070, 0.92),
    ("Search - Summer Sale 2026", "Search", "2026-07-01", "2026-07-21", 0.070, 0.95),
]
# Relative traffic weight of each Google campaign within paid search
GOOGLE_WEIGHTS = {"Search - Brand": 30, "Search - Generic - Climbing Shoes": 18, "Search - Generic - Crash Pads": 7,
                  "Search - Generic - Hardware": 7, "Shopping - All Products": 25, "PMax - All Products": 30}
GOOGLE_SEASONAL_WEIGHT = 25

# Meta campaigns: name, start, end, ad sets
META_CAMPAIGNS = [
    ("Prospecting - Broad", "2023-11-01", "2024-12-31", ["BE-NL | 18-45 | Broad", "FR-DE-LU | 18-45 | Broad"]),
    ("Prospecting - Lookalike 1% Buyers", "2024-02-01", "2025-06-30", ["LAL 1% | All countries", "LAL 1% | BE-NL"]),
    ("Prospecting - Advantage+ Shopping", "2025-01-01", "2026-10-31", ["Advantage+ | All countries"]),
    ("Retargeting - Viewed or ATC 14d", "2023-11-01", "2026-10-31", ["RT | ATC 14d", "RT | Viewed 14d", "RT | Engagers 30d"]),
    ("BF 2023 - Prospecting", "2023-11-10", "2023-11-28", ["BF | Broad", "BF | Interests climbing"]),
    ("BF 2024 - Prospecting", "2024-11-12", "2024-12-03", ["BF | Broad", "BF | Interests climbing"]),
    ("BF 2025 - Prospecting", "2025-11-11", "2025-12-02", ["BF | Broad", "BF | LAL buyers"]),
    ("Spring Outdoor 2025 - Prospecting", "2025-03-15", "2025-04-10", ["Outdoor | Interests bouldering"]),
    ("Spring Outdoor 2026 - Prospecting", "2026-03-15", "2026-04-10", ["Outdoor | Interests bouldering"]),
    ("Summer Sale 2024 - Retargeting", "2024-07-01", "2024-07-21", ["Sale | Past buyers 365d"]),
    ("Summer Sale 2025 - Retargeting", "2025-07-01", "2025-07-21", ["Sale | Past buyers 365d"]),
    ("Summer Sale 2026 - Retargeting", "2026-07-01", "2026-07-21", ["Sale | Past buyers 365d"]),
]
META_WEIGHTS = {"Prospecting - Broad": 35, "Prospecting - Lookalike 1% Buyers": 25,
                "Prospecting - Advantage+ Shopping": 45, "Retargeting - Viewed or ATC 14d": 30}
META_SEASONAL_WEIGHT = 35

# Share of anonymous (non-purchase) traffic per channel
TRAFFIC_MIX = {"organic_search": 0.30, "direct": 0.18, "paid_search": 0.18, "paid_social": 0.14,
               "referral": 0.06, "email": 0.07, "influencer": 0.04, "affiliate": 0.03}
ENGAGEMENT_RATE = {"organic_search": 0.62, "direct": 0.60, "paid_search": 0.58, "paid_social": 0.42,
                   "referral": 0.55, "email": 0.70, "influencer": 0.48, "affiliate": 0.50}
