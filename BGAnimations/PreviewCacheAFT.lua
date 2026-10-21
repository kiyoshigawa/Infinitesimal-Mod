-- One ActorFrameTexture for one player, created on demand by the preview cache host.
--
-- The host sets InfinitesimalPreviewAFTPN and InfinitesimalPreviewAFTWidth before
-- loading this file. The width is part of the actor and texture name so that a change
-- in player count (1P 640 wide, 2P 320 wide) can create a new render target without
-- tripping "Texture Name already in use"; the host hides the superseded one.

local pn = InfinitesimalPreviewAFTPN
local width = InfinitesimalPreviewAFTWidth
local pnShort = ToEnumShortString(pn)

return Def.ActorFrameTexture {
	Name = "PreviewCacheAFT_" .. pnShort .. "_" .. tostring(width),

	InitCommand=function(self)
		self:SetTextureName("InfinitesimalPreview" .. pnShort .. "_" .. tostring(width))
		self:SetWidth(width):SetHeight(480)
		self:EnableAlphaBuffer(true):Create()
		-- Hidden by default: a hidden AFT does not render, so it costs nothing while
		-- the wheel is not on screen. The host shows it when a chart is being shown.
		self:visible(false)
	end,
}
