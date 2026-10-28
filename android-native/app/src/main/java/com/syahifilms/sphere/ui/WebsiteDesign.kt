package com.syahifilms.sphere.ui

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import coil.ImageLoader
import coil.compose.AsyncImage
import coil.decode.SvgDecoder
import coil.request.ImageRequest
import com.syahifilms.sphere.R
import com.syahifilms.sphere.data.Profile

// Visual-only native Compose counterparts to Sphere's original website design.
// Assets are bundled from /img in the same GitHub repo; no WebView and no external icon CDN.
object WebsiteColors {
    val Plum = Color(0xFF25163A)
    val Violet = Color(0xFF7736E8)
    val Lilac = Color(0xFFE7CBFB)
    val Peach = Color(0xFFFFD7B1)
    val Pink = Color(0xFFF8BAEB)
    val Soft = Color(0xFFFFF0F8)
    val Muted = Color(0xFF6F647B)
    val Accent = Brush.horizontalGradient(listOf(Color(0xFF7A31EA), Color(0xFFDD51C8), Color(0xFFFF9977)))
    val Backdrop = Brush.verticalGradient(listOf(Color(0xFFF0C5F6),Color(0xFFFFE3CC),Color(0xFFF7D8EF),Color(0xFFEBC9FD)))
    val Glass = Brush.linearGradient(listOf(Color(0xF9FFFFFF),Color(0xD8FFF5FE),Color(0xE8FFE9EC)))
}

@Composable
fun GlassPanel(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(24.dp)
    val clickable = if (onClick != null) Modifier.clickable { onClick() } else Modifier
    Column(
        modifier
            .shadow(5.dp, shape, ambientColor = Color(0x339555B5))
            .clip(shape)
            .background(WebsiteColors.Glass)
            .border(1.dp, Color(0xD9FFFFFF), shape)
            .then(clickable)
            .padding(15.dp),
        content = content
    )
}

@Composable
fun WebsiteArt(@DrawableRes res: Int, label: String, modifier: Modifier = Modifier, scale: ContentScale = ContentScale.Fit) {
    Image(painter = painterResource(res), contentDescription = label, modifier = modifier, contentScale = scale)
}

@Composable
fun EditorWebsiteSvg(asset: String, label: String, modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    val loader = remember(ctx) { ImageLoader.Builder(ctx).components { add(SvgDecoder.Factory()) }.build() }
    val request = remember(ctx, asset) {
        ImageRequest.Builder(ctx).data("file:///android_asset/editor/" + asset + ".svg").build()
    }
    AsyncImage(model = request, contentDescription = label, imageLoader = loader, modifier = modifier, contentScale = ContentScale.Fit)
}

@Composable
fun WebsiteHomeHeader(nav: NavHostController, editor: Boolean = false) {
    Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        val iconShape = RoundedCornerShape(17.dp)
        for ((emoji, dest) in listOf("🔔" to "notifications", "⚙️" to "settings")) {
            Box(
                Modifier.padding(end = 9.dp).size(49.dp)
                    .shadow(5.dp, iconShape).clip(iconShape)
                    .background(Brush.linearGradient(listOf(Color(0xFFCE85F8),Color(0xFF9951DD))))
                    .border(1.dp, Color(0xAFFFFFFF), iconShape)
                    .clickable { nav.go(dest) },
                contentAlignment = Alignment.Center
            ) { Text(emoji, fontSize = 25.sp) }
        }
        Spacer(Modifier.weight(1f))
        WebsiteArt(R.drawable.sphere_header,"Sphere",Modifier.size(40.dp))
        Text("Sphere", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = WebsiteColors.Plum)
        if (editor) {
            Spacer(Modifier.width(5.dp))
            Text("EDITOR",fontSize=9.sp,fontWeight=FontWeight.Bold,color=WebsiteColors.Violet)
        }
    }
}

@Composable
fun WebsiteWelcome(me: Profile, subtitle: String = "Welcome to Sphere") {
    GlassPanel(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 11.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Avatar(me.avatarUrl, me.name, 62.dp)
            Spacer(Modifier.width(13.dp))
            Column {
                Text("Hi, ${me.firstName} 👋",fontSize=23.sp,fontWeight=FontWeight.ExtraBold,color=WebsiteColors.Plum)
                Text(subtitle,color=WebsiteColors.Muted,fontSize=13.sp)
            }
        }
    }
}

@Composable
fun WebsiteSectionTitle(text: String, onAll: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(top=16.dp,bottom=12.dp),verticalAlignment=Alignment.CenterVertically){
        Text(text,Modifier.weight(1f),fontWeight=FontWeight.ExtraBold,fontSize=21.sp,color=WebsiteColors.Plum)
        if(onAll!=null) Text("See all ›",modifier=Modifier.clip(RoundedCornerShape(10.dp)).clickable { onAll() }.padding(6.dp),
            color=WebsiteColors.Violet,fontSize=13.sp,fontWeight=FontWeight.Bold)
    }
}

@Composable
fun WebsitePremium(onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.End){
        Row(Modifier.padding(vertical=6.dp).clip(RoundedCornerShape(28.dp))
            .background(WebsiteColors.Accent).clickable(onClick=onClick)
            .padding(horizontal=22.dp,vertical=12.dp),verticalAlignment=Alignment.CenterVertically){
            Text("💎",fontSize=22.sp)
            Spacer(Modifier.width(8.dp))
            Text("Get Premium",color=Color.White,fontSize=16.sp,fontWeight=FontWeight.ExtraBold)
        }
    }
}

@Composable
fun WebsiteExploreRow(onClick: (String)->Unit) {
    val shortcuts = listOf(
        Triple("Saved", R.drawable.explore_saved, "saved"),
        Triple("All Editors", R.drawable.explore_editors, "editors"),
        Triple("Sphere AI", R.drawable.explore_ai, "ai"),
        Triple("Verified PC", R.drawable.explore_pc, "verifiedPc"),
        Triple("Vault", R.drawable.explore_vault, "vault")
    )
    Row(Modifier.fillMaxWidth(), horizontalArrangement=Arrangement.spacedBy(4.dp)) {
        shortcuts.forEach { (label, art, route) ->
            Column(Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).clickable { onClick(route) }
                .padding(vertical=4.dp),horizontalAlignment=Alignment.CenterHorizontally) {
                Box(Modifier.fillMaxWidth().aspectRatio(1f).padding(1.dp)
                    .clip(CircleShape).background(Color(0xEFFFFFFF))
                    .border(1.dp,Color.White,CircleShape).padding(3.dp),contentAlignment=Alignment.Center){
                    WebsiteArt(art,label,Modifier.fillMaxSize())
                }
                Spacer(Modifier.height(5.dp))
                Text(label,fontSize=10.sp,lineHeight=12.sp,fontWeight=FontWeight.Bold,
                    textAlign=TextAlign.Center,maxLines=2,color=WebsiteColors.Plum)
            }
        }
    }
}

@Composable
fun WebsiteToolGrid(onClick: (String)->Unit) {
    val tools=listOf(
        Triple("Verified\nPortfolios",R.drawable.tool_portfolios,"editors"),
        Triple("Project\nShowcase",R.drawable.tool_showcase,"jobs"),
        Triple("SafePay\nEscrow",R.drawable.tool_escrow,"escrow")
    )
    GlassPanel(Modifier.fillMaxWidth()) {
        WebsiteSectionTitle("Tools & Resources")
        Row(horizontalArrangement=Arrangement.spacedBy(10.dp)) {
            tools.forEach { (label,art,route) ->
                Column(Modifier.weight(1f).clip(RoundedCornerShape(20.dp)).clickable { onClick(route) },
                    horizontalAlignment=Alignment.CenterHorizontally){
                    Box(Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(20.dp))
                        .background(Color.White).padding(7.dp)){
                        WebsiteArt(art,label.replace("\n"," "),Modifier.fillMaxSize())
                    }
                    Text(label,textAlign=TextAlign.Center,fontSize=11.sp,lineHeight=14.sp,
                        fontWeight=FontWeight.SemiBold,color=WebsiteColors.Plum,modifier=Modifier.padding(top=7.dp,bottom=5.dp))
                }
            }
        }
    }
}

@Composable
fun WebsiteServiceGrid(onClick: (String)->Unit) {
    val tiles=listOf(
        Triple("Post a Job",R.drawable.service_post,"postJob"),
        Triple("Talent Search",R.drawable.service_talent,"editors"),
        Triple("My Projects",R.drawable.service_projects,"jobs"),
        Triple("Message",R.drawable.service_messages,"chats"),
        Triple("Payments",R.drawable.service_payments,"payments"),
        Triple("Profile",R.drawable.service_profile,"profile")
    )
    GlassPanel(Modifier.fillMaxWidth()) {
        WebsiteSectionTitle("Sphere Services")
        tiles.chunked(3).forEach { row ->
            Row(horizontalArrangement=Arrangement.spacedBy(9.dp),modifier=Modifier.padding(bottom=9.dp)) {
                row.forEach { (label,art,route) ->
                    WebsiteArt(
                        art,label,
                        Modifier.weight(1f).aspectRatio(1f)
                            .clip(RoundedCornerShape(19.dp)).clickable { onClick(route) },
                        ContentScale.Fit
                    )
                }
            }
        }
    }
}

@Composable
fun EditorShortcutGrid(nav: NavHostController) {
    WebsiteSectionTitle("Quick Actions",onAll={nav.go("jobs")})
    val actions = listOf(
        Triple("Find Jobs","available-jobs","jobs"),
        Triple("My Work","active-projects","jobs"),
        Triple("Portfolio","portfolio","portfolio"),
        Triple("Earnings","earnings","earnings")
    )
    Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(8.dp)){
        actions.forEach { (label,asset,route) ->
            Column(Modifier.weight(1f).clip(RoundedCornerShape(19.dp))
                .background(Color(0xDDFFFFFF)).clickable { nav.go(route) }.padding(6.dp),
                horizontalAlignment=Alignment.CenterHorizontally) {
                EditorWebsiteSvg(asset,label,Modifier.fillMaxWidth().aspectRatio(1f))
                Text(label,maxLines=1,overflow=TextOverflow.Ellipsis,
                    fontSize=10.sp,fontWeight=FontWeight.Bold,color=WebsiteColors.Plum)
            }
        }
    }
}
