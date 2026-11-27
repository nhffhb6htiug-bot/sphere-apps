@file:OptIn(ExperimentalMaterial3Api::class)
package com.syahifilms.sphere.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.syahifilms.sphere.R
import com.syahifilms.sphere.data.Config

/** Compose port of the web auth/onboarding CSS and original assets at main ba3950b. */
@Composable
private fun authBackdrop():Modifier {
    val dark=SphereAppearance.dark
    val base=WebsiteColors.Backdrop
    return Modifier.background(base).drawBehind {
        if(!dark){
            fun glow(color:Color,x:Float,y:Float,r:Float){
                drawRect(Brush.radialGradient(listOf(color,Color.Transparent),center=Offset(size.width*x,size.height*y),radius=(size.width*r).coerceAtLeast(1f)))
            }
            glow(Color(0x91C072FF),.06f,0f,.82f)
            glow(Color(0xC4FFD5AD),1.01f,.13f,.80f)
            glow(Color(0x94FFAEAD).copy(alpha=.58f),0f,.59f,.80f)
            glow(Color(0x8FC0ABFF),1f,.88f,.82f)
        }
    }
}

private data class Intro(val image:Int,val title:String,val desc:String)
private val introductions=listOf(
    Intro(R.drawable.onboard_hire,"Hire Top Editors","Connect instantly with professional video editors, VFX artists, and color graders."),
    Intro(R.drawable.onboard_chat,"Direct Editor Chat","Share raw footage, review cuts, and deliver final files securely."),
    Intro(R.drawable.onboard_vault,"Secure Project Vault","Track editing milestones and manage final file deliveries with real-time updates.")
)

@Composable
fun NativeOnboardingScreen(nav:NavHostController,page:Int){
    val item=introductions[page.coerceIn(0,2)]
    Box(Modifier.fillMaxSize().then(authBackdrop()).safeDrawingPadding(),contentAlignment=Alignment.TopCenter){
        Column(Modifier.widthIn(max=480.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal=20.dp),
            horizontalAlignment=Alignment.CenterHorizontally){
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.End){
                TextButton(onClick={nav.resetTo("welcome")}){Text("Skip ›",color=Muted)}
            }
            Spacer(Modifier.height(20.dp))
            Image(painterResource(item.image),item.title,Modifier.size(280.dp),contentScale=ContentScale.Fit)
            Spacer(Modifier.height(10.dp))
            Text(item.title,fontWeight=FontWeight.Bold,fontSize=24.sp,color=WebsiteColors.Plum,textAlign=TextAlign.Center)
            Spacer(Modifier.height(10.dp))
            Text(item.desc,color=Muted,fontSize=14.sp,lineHeight=20.sp,textAlign=TextAlign.Center,modifier=Modifier.padding(horizontal=10.dp))
            Row(Modifier.padding(vertical=20.dp),horizontalArrangement=Arrangement.spacedBy(6.dp)){
                repeat(3){i->Box(Modifier.width(if(i==page)20.dp else 8.dp).height(8.dp).clip(CircleShape).background(if(i==page)Blue else PanelLine))}
            }
            PrimaryButton(if(page==2)"Get Started" else "Next"){
                if(page==2)nav.resetTo("welcome") else nav.go("onboard/"+(page+1))
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
fun AuthLandingLayout(googleVisible:Boolean,googleReady:Boolean,busy:Boolean,onGoogle:()->Unit,onLogin:()->Unit,onSignup:()->Unit){
    val ctx=LocalContext.current
    BoxWithConstraints(Modifier.fillMaxSize().then(authBackdrop()).safeDrawingPadding(),contentAlignment=Alignment.TopCenter){
        val minHeight=maxHeight*.80f
        Column(Modifier.widthIn(max=480.dp).fillMaxWidth().verticalScroll(rememberScrollState()).heightIn(min=minHeight).padding(horizontal=20.dp,vertical=20.dp),
            horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.Center){
            Image(painterResource(R.drawable.auth_landing),"Sphere",Modifier.size(120.dp).clip(RoundedCornerShape(20.dp)),contentScale=ContentScale.Fit)
            Spacer(Modifier.height(16.dp))
            Text("Sphere",fontSize=28.sp,fontWeight=FontWeight.Black,color=Blue)
            Spacer(Modifier.height(30.dp))
            if(googleVisible){
                Button(onClick=onGoogle,enabled=googleReady&&!busy,modifier=Modifier.fillMaxWidth().heightIn(min=44.dp),
                    shape=RoundedCornerShape(24.dp),border=BorderStroke(1.dp,PanelLine),
                    colors=ButtonDefaults.buttonColors(containerColor=Color.White,contentColor=Color(0xFF111111),disabledContainerColor=Color.White.copy(alpha=.75f),disabledContentColor=Color(0xFF606780))){
                    Image(painterResource(R.drawable.google_g),"Google",Modifier.size(18.dp))
                    Spacer(Modifier.width(10.dp))
                    Text(if(busy)"Signing in…" else "Continue with Google",fontWeight=FontWeight.SemiBold)
                }
                if(!googleReady)Text("Google login is unavailable in this staging build.",fontSize=11.sp,color=Muted,textAlign=TextAlign.Center,modifier=Modifier.padding(top=5.dp))
                Spacer(Modifier.height(14.dp))
                Text("or",color=Muted,fontSize=13.sp)
                Spacer(Modifier.height(14.dp))
            }
            Button(onClick=onLogin,enabled=!busy,modifier=Modifier.fillMaxWidth().heightIn(min=50.dp),
                shape=RoundedCornerShape(30.dp),colors=ButtonDefaults.buttonColors(containerColor=Color(0xFF29243B),contentColor=Color.White)){
                Text("Log In",fontWeight=FontWeight.Bold,fontSize=15.sp)
            }
            Spacer(Modifier.height(10.dp))
            OutlinedButton(onClick=onSignup,enabled=!busy,
                modifier=Modifier.fillMaxWidth().heightIn(min=50.dp).clip(RoundedCornerShape(30.dp)).background(WebsiteColors.Glass),
                shape=RoundedCornerShape(30.dp),border=BorderStroke(1.dp,PanelLine)){
                Text("Sign Up",color=Blue,fontWeight=FontWeight.Bold,fontSize=15.sp)
            }
            Spacer(Modifier.height(14.dp))
            Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.Center,verticalAlignment=Alignment.CenterVertically){
                listOf("Terms" to "/terms.html","Privacy" to "/privacy.html","Refund" to "/refund.html","Contact" to "/contact.html").forEach{(label,path)->
                    TextButton(onClick={openUrl(ctx,Config.WEBSITE+path)},contentPadding=PaddingValues(horizontal=6.dp,vertical=4.dp)){Text(label,fontSize=12.sp,color=Blue)}
                }
            }
            Text("Staging preview · Test accounts only",fontSize=11.sp,color=Muted,textAlign=TextAlign.Center)
        }
    }
}

@Composable
fun AuthFormLayout(title:String,subtitle:String="",onBack:()->Unit,content:@Composable ColumnScope.()->Unit){
    Box(Modifier.fillMaxSize().then(authBackdrop()).safeDrawingPadding().imePadding(),contentAlignment=Alignment.TopCenter){
        Column(Modifier.widthIn(max=480.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp)){
            IconButton(onClick=onBack,modifier=Modifier.clip(CircleShape).background(WebsiteColors.Glass)){
                Icon(Icons.AutoMirrored.Filled.ArrowBack,"Back",tint=WebsiteColors.Plum)
            }
            Spacer(Modifier.height(12.dp))
            Text(title,fontSize=24.sp,fontWeight=FontWeight.Bold,color=WebsiteColors.Plum)
            if(subtitle.isNotBlank()){Spacer(Modifier.height(5.dp));Text(subtitle,color=Muted,fontSize=14.sp)}
            Spacer(Modifier.height(20.dp))
            content()
        }
    }
}

@Composable
fun AuthField(value:String,onChange:(String)->Unit,label:String,placeholder:String,keyboard:KeyboardType=KeyboardType.Text,secret:Boolean=false,phonePrefix:Boolean=false){
    Column(Modifier.fillMaxWidth().padding(bottom=16.dp)){
        Text(label,fontSize=13.sp,fontWeight=FontWeight.SemiBold,color=WebsiteColors.Plum)
        Spacer(Modifier.height(6.dp))
        OutlinedTextField(value=value,onValueChange=onChange,placeholder={Text(placeholder,color=Muted,fontSize=14.sp)},
            singleLine=true,keyboardOptions=KeyboardOptions(keyboardType=keyboard),
            visualTransformation=if(secret)PasswordVisualTransformation() else VisualTransformation.None,
            prefix=if(phonePrefix){{Text("+91",fontWeight=FontWeight.SemiBold)}} else null,
            modifier=Modifier.fillMaxWidth(),shape=RoundedCornerShape(17.dp),
            colors=OutlinedTextFieldDefaults.colors(focusedContainerColor=PanelSurface,unfocusedContainerColor=PanelSurface.copy(alpha=.94f),focusedBorderColor=Blue,unfocusedBorderColor=PanelLine))
    }
}
