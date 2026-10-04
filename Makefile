# ============================================================
# OneFileLinux Makefile
#   make build   - 打包 initramfs 并构建 UKI
#   make run     - 启动 QEMU 测试
#   make clean   - 清理产物
# ============================================================

# ---------- 路径与变量 ----------

MINIROOTFS := alpine-minirootfs
INITRAMFS  := initramfs.img
UKI        := OneFileLinux.efi
KERNEL     := ./prebuilt/vmlinuz-lts
CMDLINE    := ./config/cmdline

OVMF_CODE     := /usr/share/edk2/x64/OVMF_CODE.4m.fd
OVMF_VARS     := /usr/share/edk2/x64/OVMF_VARS.4m.fd
OVMF_VARS_TMP := /tmp/OVMF_VARS.4m.fd

TEST_DIR := QEMU
BOOT_DIR := $(TEST_DIR)/EFI/BOOT
BOOTX64  := $(BOOT_DIR)/BOOTX64.efi

QEMU       := qemu-system-x86_64
QEMU_FLAGS := -enable-kvm -m 4096 -cpu host -machine q35 \
              -drive if=pflash,format=raw,readonly=on,file=$(OVMF_CODE) \
              -drive if=pflash,format=raw,file=$(OVMF_VARS_TMP) \
              -drive format=raw,file=fat:rw:./$(TEST_DIR) \
              -netdev user,id=net0 \
              -device virtio-net-pci,netdev=net0 \
              -serial stdio

.PHONY: all build run clean FORCE

# ---------- 默认目标 ----------

all: build

# ---------- 构建 ----------

build: $(UKI)

# 打包 initramfs
# 用 FORCE 强制每次重建：minirootfs 是目录，内部文件变动不会更新目录 mtime，
# 依赖追踪不可靠，所以直接每次重新打包。
$(INITRAMFS): FORCE
	@echo "==> 打包 initramfs"
	rm -f $(INITRAMFS)
	cd $(MINIROOTFS) && find . -print0 | cpio \
	    --null \
	    -o \
	    --format=newc \
	    --owner=0:0 \
	    | zstd -z > $(CURDIR)/$(INITRAMFS)

# 构建 UKI
$(UKI): $(INITRAMFS) $(KERNEL) $(CMDLINE)
	@echo "==> 构建 UKI"
	ukify build \
	    --linux=$(KERNEL) \
	    --initrd=$(INITRAMFS) \
	    --cmdline=@$(CMDLINE) \
	    --output=$(UKI)

# ---------- 运行 QEMU ----------

run: $(BOOTX64)
	@echo "==> 启动 QEMU"
	cp $(OVMF_VARS) $(OVMF_VARS_TMP)
	$(QEMU) $(QEMU_FLAGS)

# 把 UKI 复制到 ESP 目录结构
$(BOOTX64): $(UKI)
	mkdir -p $(BOOT_DIR)
	cp $(UKI) $(BOOTX64)

# ---------- 清理 ----------

clean:
	rm -f $(INITRAMFS) $(UKI)
	rm -rf $(TEST_DIR)
	rm -f $(OVMF_VARS_TMP)

# 用于强制重建的伪目标
FORCE: