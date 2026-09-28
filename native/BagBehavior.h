#pragma once
// Only the Mageweave pouch family (including the retired Olive variant) is
// soft. Other bags, including the older Runecloth backpack, remain rigid.
static inline bool bagSoftBody(unsigned model){return model>=12&&model<=16;}
