#include "texture_bridge_gpu.h"

#include <algorithm>
#include <iostream>

#include "util/direct3d11.interop.h"

TextureBridgeGpu::TextureBridgeGpu(
    GraphicsContext* graphics_context,
    ABI::Windows::UI::Composition::IVisual* visual)
    : TextureBridge(graphics_context, visual) {
  surface_descriptor_.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
  surface_descriptor_.format =
      kFlutterDesktopPixelFormatNone;  // no format required for DXGI surfaces
}

void TextureBridgeGpu::ProcessFrame(winrt::com_ptr<ID3D11Texture2D> src_texture,
                                    size_t requested_width,
                                    size_t requested_height) {
  D3D11_TEXTURE2D_DESC desc;
  src_texture->GetDesc(&desc);

  EnsureSurface(static_cast<uint32_t>(requested_width),
                static_cast<uint32_t>(requested_height));

  auto device_context = graphics_context_->d3d_device_context();

  if (desc.Width == requested_width && desc.Height == requested_height) {
    device_context->CopyResource(surface_.get(), src_texture.get());
  } else {
    if (surface_rtv_) {
      const float transparent[4] = {0.0f, 0.0f, 0.0f, 0.0f};
      device_context->ClearRenderTargetView(surface_rtv_.get(), transparent);
    }

    D3D11_BOX src_box = {};
    src_box.right = (std::min)(desc.Width, static_cast<UINT>(requested_width));
    src_box.bottom = (std::min)(desc.Height, static_cast<UINT>(requested_height));
    src_box.back = 1;

    device_context->CopySubresourceRegion(surface_.get(), 0, 0, 0, 0,
                                          src_texture.get(), 0, &src_box);
  }

  device_context->Flush();
}

void TextureBridgeGpu::EnsureSurface(uint32_t width, uint32_t height) {
  if (!surface_ || surface_size_.width != width ||
      surface_size_.height != height) {
    D3D11_TEXTURE2D_DESC dstDesc = {};
    dstDesc.ArraySize = 1;
    dstDesc.MipLevels = 1;
    dstDesc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    dstDesc.CPUAccessFlags = 0;
    dstDesc.Format = static_cast<DXGI_FORMAT>(kPixelFormat);
    dstDesc.Width = width;
    dstDesc.Height = height;
    dstDesc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;
    dstDesc.SampleDesc.Count = 1;
    dstDesc.SampleDesc.Quality = 0;
    dstDesc.Usage = D3D11_USAGE_DEFAULT;

    surface_ = nullptr;
    surface_rtv_ = nullptr;
    if (!SUCCEEDED(graphics_context_->d3d_device()->CreateTexture2D(
            &dstDesc, nullptr, surface_.put()))) {
      std::cerr << "Creating intermediate texture failed" << std::endl;
      return;
    }

    graphics_context_->d3d_device()->CreateRenderTargetView(
        surface_.get(), nullptr, surface_rtv_.put());

    HANDLE shared_handle;
    surface_.try_as(dxgi_surface_);
    assert(dxgi_surface_);
    dxgi_surface_->GetSharedHandle(&shared_handle);

    surface_descriptor_.handle = shared_handle;
    surface_descriptor_.width = surface_descriptor_.visible_width = width;
    surface_descriptor_.height = surface_descriptor_.visible_height = height;
    surface_descriptor_.release_context = surface_.get();
    surface_descriptor_.release_callback = [](void* release_context) {
      auto texture = reinterpret_cast<ID3D11Texture2D*>(release_context);
      texture->Release();
    };

    surface_size_ = {width, height};
  }
}

const FlutterDesktopGpuSurfaceDescriptor*
TextureBridgeGpu::GetSurfaceDescriptor(size_t width, size_t height) {
  const std::lock_guard<std::mutex> lock(mutex_);

  if (!is_running_) {
    return nullptr;
  }

  if (last_frame_) {
    ProcessFrame(last_frame_, width, height);
  }

  if (surface_) {
    // Gets released in the SurfaceDescriptor's release callback.
    surface_->AddRef();
  }

  return &surface_descriptor_;
}

void TextureBridgeGpu::StopInternal() {
  TextureBridge::StopInternal();

  // For some reason, the destination surface needs to be recreated upon
  // resuming. Force |EnsureSurface| to create a new one by resetting it here.
  surface_ = nullptr;
  surface_rtv_ = nullptr;
}
