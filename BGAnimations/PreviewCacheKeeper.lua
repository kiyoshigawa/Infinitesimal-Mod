-- Keeps a preview render target alive for the life of the cache host.
--
-- AFT render targets are reference counted and are deleted when the last reference
-- goes away. The wheel's sprite is the only normal reference, and it dies with the
-- wheel screen, which deleted the target while the host still owned the AFT: the next
-- bind attempted to load the name from disk and fell back to a blank texture (black
-- preview after playing a song).
--
-- This sprite holds one reference permanently. The load is explicit in InitCommand:
-- assigning Texture= and leaving the actor hidden/hardly drawn is not enough, because
-- the texture would only be taken when the sprite is first used.
--
-- The host sets InfinitesimalPreviewKeeperTexture before loading this file.

local texture = InfinitesimalPreviewKeeperTexture

return Def.Sprite {
	Name = "PreviewCacheKeeper_" .. tostring(texture),

	InitCommand=function(self)
		self:Load(texture)
		self:xy(-10000, -10000):visible(false)
	end,
}
