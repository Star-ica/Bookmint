// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 v) external returns (bool);
    function transferFrom(address f, address t, uint256 v) external returns (bool);
}

/// @title BookMint - onchain book registry, access rights, payments and royalties.
/// @dev Modules (sections): AuthorRegistry, BookRegistry, Pricing, PurchaseRegistry,
///      RevenueSplit, WithdrawalManager, FeeManager, Moderation. Ebook bytes are NOT stored
///      onchain; `contentRef` is an external pointer and is publicly readable (disclosed limitation).
contract BookMint {
    address public admin;
    address public immutable BOT;
    address public immutable USDT;
    bool public platformPaused;
    uint16 public feeBps = 250;
    uint16 public constant MAX_FEE_BPS = 1000;
    uint16 public maxRoyaltyBps = 5000;
    uint256 public maxPrice = type(uint256).max;
    bool private _lock;

    struct Author { string name; string bio; string avatarRef; bool exists; }
    struct Book {
        address author; string title; string description; string category; string language;
        string coverRef; string contentRef; address royaltyTo; uint16 royaltyBps;
        bool published; bool paused; bool allowRepurchase; uint32 sales; uint64 createdAt;
    }

    mapping(address => Author) public authors;
    address[] public authorList;
    Book[] private _books;
    mapping(uint256 => mapping(address => uint256)) public price;
    mapping(uint256 => mapping(address => uint32)) public accessCount;
    mapping(address => uint256[]) private _library;
    mapping(address => mapping(address => uint256)) public balances;
    mapping(uint256 => mapping(address => bool)) public reported;
    mapping(uint256 => uint32) public reportCount;
    mapping(address => mapping(address => uint256)) public earned;

    event AuthorSet(address indexed author, string name);
    event BookRegistered(uint256 indexed id, address indexed author);
    event BookUpdated(uint256 indexed id);
    event PriceSet(uint256 indexed id, address indexed token, uint256 amount);
    event Purchased(uint256 indexed id, address indexed buyer, address indexed token, uint256 amount, uint256 fee);
    event Withdrawn(address indexed account, address indexed token, uint256 amount);
    event Reported(uint256 indexed id, address indexed by, string reason);
    event Moderated(uint256 indexed id, bool paused);

    modifier onlyAdmin() { require(msg.sender == admin, "admin only"); _; }
    modifier nonReentrant() { require(!_lock, "reentrant"); _lock = true; _; _lock = false; }
    modifier bookOwner(uint256 id) { require(id < _books.length && _books[id].author == msg.sender, "not book author"); _; }

    constructor(address bot, address usdt) { admin = msg.sender; BOT = bot; USDT = usdt; }

    // AuthorRegistry
    function setProfile(string calldata name, string calldata bio, string calldata avatarRef) external {
        require(bytes(name).length > 0 && bytes(name).length <= 64, "bad name");
        if (!authors[msg.sender].exists) authorList.push(msg.sender);
        authors[msg.sender] = Author(name, bio, avatarRef, true);
        emit AuthorSet(msg.sender, name);
    }

    // BookRegistry + Pricing
    function registerBook(
        string calldata title, string calldata description, string calldata category, string calldata language,
        string calldata coverRef, string calldata contentRef, uint256 priceBot, uint256 priceUsdt,
        address royaltyTo, uint16 royaltyBps, bool allowRepurchase
    ) external returns (uint256 id) {
        require(authors[msg.sender].exists, "create profile first");
        require(!platformPaused, "platform paused");
        require(bytes(title).length > 0 && bytes(title).length <= 120, "bad title");
        require(royaltyBps <= maxRoyaltyBps && (royaltyBps == 0 || royaltyTo != address(0)), "bad royalty");
        id = _books.length;
        _books.push(Book(msg.sender, title, description, category, language, coverRef, contentRef,
            royaltyTo, royaltyBps, false, false, allowRepurchase, 0, uint64(block.timestamp)));
        _setPrice(id, BOT, priceBot);
        _setPrice(id, USDT, priceUsdt);
        emit BookRegistered(id, msg.sender);
    }

    function updateBook(uint256 id, string calldata title, string calldata description, string calldata category,
        string calldata language, string calldata coverRef, string calldata contentRef) external bookOwner(id) {
        require(bytes(title).length > 0 && bytes(title).length <= 120, "bad title");
        Book storage b = _books[id];
        b.title = title; b.description = description; b.category = category;
        b.language = language; b.coverRef = coverRef; b.contentRef = contentRef;
        emit BookUpdated(id);
    }

    function setPrices(uint256 id, uint256 priceBot, uint256 priceUsdt) external bookOwner(id) {
        _setPrice(id, BOT, priceBot); _setPrice(id, USDT, priceUsdt);
    }

    function _setPrice(uint256 id, address token, uint256 amount) internal {
        require(amount <= maxPrice, "price too high");
        price[id][token] = amount;
        emit PriceSet(id, token, amount);
    }

    function setPublished(uint256 id, bool on) external bookOwner(id) {
        require(!on || (price[id][BOT] > 0 || price[id][USDT] > 0), "set a price first");
        _books[id].published = on; emit BookUpdated(id);
    }

    // PurchaseRegistry + RevenueSplit
    function purchase(uint256 id, address token) external nonReentrant {
        require(!platformPaused, "platform paused");
        require(id < _books.length, "no book");
        Book storage b = _books[id];
        require(b.published && !b.paused, "unavailable");
        require(token == BOT || token == USDT, "bad token");
        uint256 p = price[id][token];
        require(p > 0, "token not accepted");
        require(msg.sender != b.author, "author owns book");
        require(b.allowRepurchase || accessCount[id][msg.sender] == 0, "already owned");

        require(IERC20(token).transferFrom(msg.sender, address(this), p), "payment failed");
        uint256 fee = (p * feeBps) / 10000;
        uint256 net = p - fee;
        uint256 royalty = b.royaltyTo == address(0) ? 0 : (net * b.royaltyBps) / 10000;
        balances[admin][token] += fee;
        if (royalty > 0) { balances[b.royaltyTo][token] += royalty; earned[b.royaltyTo][token] += royalty; }
        balances[b.author][token] += net - royalty;
        earned[b.author][token] += net - royalty;

        if (accessCount[id][msg.sender] == 0) _library[msg.sender].push(id);
        accessCount[id][msg.sender] += 1;
        b.sales += 1;
        emit Purchased(id, msg.sender, token, p, fee);
    }

    function hasAccess(uint256 id, address user) public view returns (bool) {
        return id < _books.length && (accessCount[id][user] > 0 || _books[id].author == user);
    }

    // WithdrawalManager (pull payments, checks-effects-interactions)
    function withdraw(address token) external nonReentrant {
        uint256 amt = balances[msg.sender][token];
        require(amt > 0, "nothing to withdraw");
        balances[msg.sender][token] = 0;
        require(IERC20(token).transfer(msg.sender, amt), "transfer failed");
        emit Withdrawn(msg.sender, token, amt);
    }

    // Moderation
    function report(uint256 id, string calldata reason) external {
        require(id < _books.length && !reported[id][msg.sender], "invalid/duplicate");
        reported[id][msg.sender] = true; reportCount[id] += 1;
        emit Reported(id, msg.sender, reason);
    }
    function moderate(uint256 id, bool paused) external onlyAdmin { _books[id].paused = paused; emit Moderated(id, paused); }

    // FeeManager / rules
    function setFeeBps(uint16 bps) external onlyAdmin { require(bps <= MAX_FEE_BPS, "fee too high"); feeBps = bps; }
    function setRules(uint16 _maxRoyaltyBps, uint256 _maxPrice) external onlyAdmin {
        require(_maxRoyaltyBps <= 10000, "bad bps"); maxRoyaltyBps = _maxRoyaltyBps; maxPrice = _maxPrice;
    }
    function setPlatformPaused(bool p) external onlyAdmin { platformPaused = p; }
    function transferAdmin(address a) external onlyAdmin { require(a != address(0), "zero"); admin = a; }

    // views
    function bookCount() external view returns (uint256) { return _books.length; }
    function getBook(uint256 id) external view returns (Book memory) { return _books[id]; }
    function libraryOf(address u) external view returns (uint256[] memory) { return _library[u]; }
    function authorCount() external view returns (uint256) { return authorList.length; }
}
