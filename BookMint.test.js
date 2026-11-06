const { expect } = require("chai"); const { ethers } = require("hardhat");
describe("BookMint", () => {
  let bm, bot, usdt, admin, author, reader, other, B; const P = 1000n;
  beforeEach(async () => {
    [admin, author, reader, other] = await ethers.getSigners();
    const T = await ethers.getContractFactory("MockERC20");
    bot = await T.deploy("BOT"); usdt = await T.deploy("USDT"); B = await bot.getAddress();
    bm = await (await ethers.getContractFactory("BookMint")).deploy(B, await usdt.getAddress());
    await bm.connect(author).setProfile("Ada", "bio", "");
    await bm.connect(author).registerBook("T","d","Fiction","EN","","ref://x",P,P,ethers.ZeroAddress,0,false);
    await bot.mint(reader.address, 10000n); await bot.connect(reader).approve(await bm.getAddress(), 10000n);
  });
  it("blocks listing changes by non-authors", async () => {
    await expect(bm.connect(other).setPublished(0,true)).to.be.revertedWith("not book author");
    await expect(bm.connect(other).setPrices(0,1,1)).to.be.revertedWith("not book author");
  });
  it("requires publish before purchase", async () => {
    await expect(bm.connect(reader).purchase(0, B)).to.be.revertedWith("unavailable");
  });
  it("splits payment, grants access, blocks duplicates", async () => {
    await bm.connect(author).setPublished(0,true);
    await bm.connect(reader).purchase(0, B);
    expect(await bm.hasAccess(0, reader.address)).to.equal(true);
    expect(await bm.balances(admin.address, B)).to.equal(25n);
    expect(await bm.balances(author.address, B)).to.equal(975n);
    await expect(bm.connect(reader).purchase(0, B)).to.be.revertedWith("already owned");
  });
  it("pays royalties and lets author withdraw once", async () => {
    await bm.connect(author).registerBook("R","d","c","EN","","",P,P,other.address,2000,false);
    await bm.connect(author).setPublished(1,true);
    await bm.connect(reader).purchase(1, B);
    expect(await bm.balances(other.address, B)).to.equal(195n);
    await bm.connect(author).withdraw(B);
    expect(await bot.balanceOf(author.address)).to.equal(780n);
    await expect(bm.connect(author).withdraw(B)).to.be.revertedWith("nothing to withdraw");
  });
  it("admin-only moderation and fee cap", async () => {
    await expect(bm.connect(other).moderate(0,true)).to.be.revertedWith("admin only");
    await expect(bm.setFeeBps(1001)).to.be.revertedWith("fee too high");
    await bm.connect(author).setPublished(0,true); await bm.moderate(0,true);
    await expect(bm.connect(reader).purchase(0, B)).to.be.revertedWith("unavailable");
  });
});
